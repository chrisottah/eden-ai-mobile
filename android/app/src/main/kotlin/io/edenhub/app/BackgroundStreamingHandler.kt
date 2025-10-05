package io.edenhub.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

// ---------------------
// SERVICE CLASS
// ---------------------
class BackgroundStreamingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private val activeStreams = mutableSetOf<String>()

    companion object {
        const val CHANNEL_ID = "eden_streaming_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "START_STREAMING"
        const val ACTION_STOP = "STOP_STREAMING"
        const val ACTION_KEEP_ALIVE = "KEEP_ALIVE"
    }

    override fun onCreate() {
        super.onCreate()
        println("BackgroundStreamingService: Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val streamCount = intent.getIntExtra("streamCount", 1)
                acquireWakeLock()
                startForegroundWithNotification(streamCount)
                println("BackgroundStreamingService: Started foreground service for $streamCount streams")
            }
            ACTION_STOP -> stopStreaming()
            ACTION_KEEP_ALIVE -> {
                val streamCount = intent.getIntExtra("streamCount", 1)
                keepAlive()
                updateNotification(streamCount)
            }
        }
        return START_STICKY
    }

    private fun startForegroundWithNotification(streamCount: Int) {
        val notification = createNotification(streamCount)
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotification(streamCount: Int): Notification {
        val title = if (streamCount == 1)
            "Eden AI streaming in progress"
        else
            "$streamCount chats streaming"

        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Processing chat responses...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setShowWhen(false)
            .setAutoCancel(false)
            .build()
    }

    private fun updateNotification(streamCount: Int) {
        try {
            NotificationManagerCompat.from(this)
                .notify(NOTIFICATION_ID, createNotification(streamCount))
        } catch (e: SecurityException) {
            println("BackgroundStreamingService: Notification permission not granted")
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "EdenAI::StreamingWakeLock"
        ).apply {
            acquire(15 * 60 * 1000L)
        }
        println("BackgroundStreamingService: Wake lock acquired")
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        println("BackgroundStreamingService: Wake lock released")
    }

    private fun keepAlive() {
        releaseWakeLock()
        acquireWakeLock()
        println("BackgroundStreamingService: Keep alive - wake lock refreshed")
    }

    private fun stopStreaming() {
        activeStreams.clear()
        releaseWakeLock()
        stopForeground(true)
        stopSelf()
        println("BackgroundStreamingService: Service stopped")
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
        println("BackgroundStreamingService: Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

// ---------------------
// HANDLER CLASS
// ---------------------
class BackgroundStreamingHandler(private val activity: MainActivity) : MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var sharedPrefs: SharedPreferences

    private val activeStreams = mutableSetOf<String>()
    private var backgroundJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    companion object {
        private const val CHANNEL_NAME = "eden/background_streaming"
        private const val PREFS_NAME = "eden_stream_states"
        private const val STREAM_STATES_KEY = "active_streams"
    }

    fun setup(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = activity.applicationContext
        sharedPrefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        createNotificationChannel()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startBackgroundExecution" -> {
                val streamIds = call.argument<List<String>>("streamIds")
                if (streamIds != null) {
                    startBackgroundExecution(streamIds)
                    result.success(null)
                } else result.error("INVALID_ARGS", "Stream IDs required", null)
            }

            "stopBackgroundExecution" -> {
                val streamIds = call.argument<List<String>>("streamIds")
                if (streamIds != null) {
                    stopBackgroundExecution(streamIds)
                    result.success(null)
                } else result.error("INVALID_ARGS", "Stream IDs required", null)
            }

            "keepAlive" -> {
                keepAlive()
                result.success(null)
            }

            "saveStreamStates" -> {
                val states = call.argument<List<Map<String, Any>>>("states")
                val reason = call.argument<String>("reason") ?: "unknown"
                if (states != null) saveStreamStates(states, reason)
                result.success(null)
            }

            "recoverStreamStates" -> result.success(recoverStreamStates())
            else -> result.notImplemented()
        }
    }

    private fun startBackgroundExecution(streamIds: List<String>) {
        activeStreams.addAll(streamIds)
        if (activeStreams.isNotEmpty()) {
            startForegroundService()
            startBackgroundMonitoring()
        }
    }

    private fun stopBackgroundExecution(streamIds: List<String>) {
        activeStreams.removeAll(streamIds.toSet())
        if (activeStreams.isEmpty()) {
            stopForegroundService()
            stopBackgroundMonitoring()
        }
    }

    private fun startForegroundService() {
        val serviceIntent = Intent(context, BackgroundStreamingService::class.java)
            .apply {
                putExtra("streamCount", activeStreams.size)
                action = BackgroundStreamingService.ACTION_START
            }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            context.startForegroundService(serviceIntent)
        else
            context.startService(serviceIntent)
    }

    private fun stopForegroundService() {
        val intent = Intent(context, BackgroundStreamingService::class.java)
            .apply { action = BackgroundStreamingService.ACTION_STOP }
        context.startService(intent)
    }

    private fun startBackgroundMonitoring() {
        backgroundJob?.cancel()
        backgroundJob = scope.launch {
            while (activeStreams.isNotEmpty()) {
                delay(30000)
                channel.invokeMethod("checkStreams", null)
            }
        }
    }

    private fun stopBackgroundMonitoring() {
        backgroundJob?.cancel()
        backgroundJob = null
    }

    private fun keepAlive() {
        val intent = Intent(context, BackgroundStreamingService::class.java)
            .apply {
                action = BackgroundStreamingService.ACTION_KEEP_ALIVE
                putExtra("streamCount", activeStreams.size)
            }
        context.startService(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Eden AI Streaming"
            val descriptionText = "Keeps chat streams active in background"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(
                BackgroundStreamingService.CHANNEL_ID,
                name,
                importance
            ).apply {
                description = descriptionText
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun saveStreamStates(states: List<Map<String, Any>>, reason: String) {
        try {
            val jsonArray = JSONArray().apply {
                for (state in states) {
                    val obj = JSONObject()
                    for ((key, value) in state) obj.put(key, value)
                    put(obj)
                }
            }
            sharedPrefs.edit()
                .putString(STREAM_STATES_KEY, jsonArray.toString())
                .putLong("saved_timestamp", System.currentTimeMillis())
                .putString("saved_reason", reason)
                .apply()
            println("BackgroundStreamingHandler: Saved ${states.size} stream states (reason: $reason)")
        } catch (e: Exception) {
            println("BackgroundStreamingHandler: Failed to save stream states: ${e.message}")
        }
    }

    private fun recoverStreamStates(): List<Map<String, Any>> {
        return try {
            val saved = sharedPrefs.getString(STREAM_STATES_KEY, null) ?: return emptyList()
            val timestamp = sharedPrefs.getLong("saved_timestamp", 0)
            val reason = sharedPrefs.getString("saved_reason", "unknown")
            val age = System.currentTimeMillis() - timestamp

            if (age > 3600000) {
                println("BackgroundStreamingHandler: Stream states too old (${age / 1000}s), discarding")
                sharedPrefs.edit().remove(STREAM_STATES_KEY).apply()
                return emptyList()
            }

            val jsonArray = JSONArray(saved)
            val result = mutableListOf<Map<String, Any>>()
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val map = mutableMapOf<String, Any>()
                obj.keys().forEachRemaining { key ->
                    map[key] = obj.get(key)
                }
                result.add(map)
            }

            println("BackgroundStreamingHandler: Recovered ${result.size} stream states (reason: $reason, age: ${age / 1000}s)")
            sharedPrefs.edit().remove(STREAM_STATES_KEY).apply()
            result
        } catch (e: Exception) {
            println("BackgroundStreamingHandler: Failed to recover stream states: ${e.message}")
            emptyList()
        }
    }

    fun cleanup() {
        scope.cancel()
        stopBackgroundMonitoring()
        stopForegroundService()
    }
}
