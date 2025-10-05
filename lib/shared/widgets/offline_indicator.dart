import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/providers/app_providers.dart';
import '../theme/theme_extensions.dart';
import 'package:eden_ai/l10n/app_localizations.dart';

part 'offline_indicator.g.dart';

class OfflineIndicator extends ConsumerWidget {
  final Widget child;

  const OfflineIndicator({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityStatus = ref.watch(connectivityStatusProvider);
    final socketConnection = ref.watch(socketConnectionStreamProvider);
    final wasOffline = ref.watch(_wasOfflineProvider);
    final socketOffline = socketConnection.maybeWhen(
      data: (state) => state == SocketConnectionState.disconnected,
      orElse: () => false,
    );

    final overlay = connectivityStatus.when(
      data: (status) {
        if ((status == ConnectivityStatus.offline || socketOffline) &&
            !wasOffline) {
          return const SizedBox.shrink();
        }
        if (wasOffline) {
          return const _BackOnlineToast();
        }
        return const SizedBox.shrink();
      },
      loading: () => const SizedBox.shrink(),
      error: (unusedError, unusedStackTrace) => const SizedBox.shrink(),
    );

    return Stack(children: [child, overlay]);
  }
}

// Tracks if the app was recently offline to enable a one-shot back-online toast
@Riverpod(keepAlive: true)
class _WasOffline extends _$WasOffline {
  @override
  bool build() {
    // Initialize based on current connectivity (assume online until proven otherwise)
    ref.listen<AsyncValue<ConnectivityStatus>>(connectivityStatusProvider, (
      prev,
      next,
    ) {
      next.when(
        data: (status) {
          if (status == ConnectivityStatus.offline) {
            state = true; // mark that we have been offline
          } else if (status == ConnectivityStatus.online && state) {
            // After we emit the toast once, clear flag shortly after
            Future.microtask(() => state = false);
          }
        },
        loading: () {},
        error: (error, stackTrace) {},
      );
    });
    return false;
  }
}

class _BackOnlineToast extends StatelessWidget {
  const _BackOnlineToast();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: kToolbarHeight + 8,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          container: true,
          liveRegion: true,
          label: AppLocalizations.of(context)!.checkConnection,
          child: Align(
            alignment: Alignment.topCenter,
            child:
                Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: context.conduitTheme.success,
                        borderRadius: BorderRadius.circular(
                          AppBorderRadius.round,
                        ),
                        boxShadow: ConduitShadows.low(context),
                      ),
                      child: Text(
                        // Reuse existing l10n; otherwise add a dedicated "Back online" key later
                        AppLocalizations.of(context)!.loadingContent,
                        style: TextStyle(
                          color: context.conduitTheme.textInverse,
                          fontSize: AppTypography.labelLarge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                    .animate(onPlay: (c) => c.forward())
                    .fadeIn(duration: const Duration(milliseconds: 200))
                    .then(delay: const Duration(milliseconds: 1200))
                    .fadeOut(duration: const Duration(milliseconds: 250)),
          ),
        ),
      ),
    );
  }
}

// Inline offline indicator for specific features
class InlineOfflineIndicator extends ConsumerWidget {
  final String message;
  final IconData? icon;
  final Color? backgroundColor;

  const InlineOfflineIndicator({
    super.key,
    this.message = '',
    this.icon,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    if (isOnline) {
      return const SizedBox.shrink();
    }

    final theme = context.conduitTheme;
    final surfaceColor = backgroundColor ?? theme.warningBackground;
    final borderAlpha = Theme.of(context).brightness == Brightness.dark
        ? 0.45
        : 0.3;

    return Container(
      margin: const EdgeInsets.all(Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: theme.warning.withValues(alpha: borderAlpha),
          width: BorderWidth.regular,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon ??
                (Platform.isIOS ? CupertinoIcons.wifi_slash : Icons.wifi_off),
            color: theme.warning,
            size: Spacing.lg,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              message.isNotEmpty
                  ? message
                  : AppLocalizations.of(context)!.featureRequiresInternet,
              style: TextStyle(
                color: theme.warning,
                fontSize: AppTypography.labelLarge,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 300));
  }
}

// Offline-aware button that disables when offline
class OfflineAwareButton extends ConsumerWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool requiresConnection;
  final String? offlineTooltip;

  const OfflineAwareButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.requiresConnection = true,
    this.offlineTooltip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final enabled = !requiresConnection || isOnline;

    return Tooltip(
      message: !enabled
          ? (offlineTooltip ??
                AppLocalizations.of(context)!.featureRequiresInternet)
          : '',
      child: FilledButton(onPressed: enabled ? onPressed : null, child: child),
    );
  }
}

// Chat-specific offline indicator
class ChatOfflineOverlay extends ConsumerWidget {
  const ChatOfflineOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    if (isOnline) {
      return const SizedBox.shrink();
    }

    final theme = context.conduitTheme;
    final surfaceColor = theme.warningBackground;
    final borderAlpha = Theme.of(context).brightness == Brightness.dark
        ? 0.5
        : 0.35;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          top: BorderSide(
            color: theme.warning.withValues(alpha: borderAlpha),
            width: BorderWidth.regular,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Platform.isIOS ? CupertinoIcons.wifi_slash : Icons.wifi_off,
            color: theme.warning,
            size: Spacing.md,
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            AppLocalizations.of(context)!.messagesWillSendWhenOnline,
            style: TextStyle(
              color: theme.warning,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 300));
  }
}
