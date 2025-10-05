import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark-reasonable.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart'
    show CodeBlockBuilder, ImageBuilder;
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:eden_ai/l10n/app_localizations.dart';

import '../../theme/theme_extensions.dart';
import '../../theme/color_tokens.dart';

class MarkdownFeatureFlags {
  const MarkdownFeatureFlags({
    this.enableSyntaxHighlighting = false,
    this.enableMermaid = false,
  });

  final bool enableSyntaxHighlighting;
  final bool enableMermaid;

  MarkdownFeatureFlags copyWith({
    bool? enableSyntaxHighlighting,
    bool? enableMermaid,
  }) {
    return MarkdownFeatureFlags(
      enableSyntaxHighlighting:
          enableSyntaxHighlighting ?? this.enableSyntaxHighlighting,
      enableMermaid: enableMermaid ?? this.enableMermaid,
    );
  }
}

class ConduitMarkdownTheme {
  const ConduitMarkdownTheme({
    required this.textStyle,
    required this.themeData,
    required this.imageBuilder,
    required this.codeBuilder,
    this.followLinkColor = true,
  });

  final TextStyle textStyle;
  final GptMarkdownThemeData themeData;
  final ImageBuilder imageBuilder;
  final CodeBlockBuilder codeBuilder;
  final bool followLinkColor;
}

class ConduitMarkdownConfig {
  static ConduitMarkdownTheme resolve(
    BuildContext context, {
    MarkdownFeatureFlags flags = const MarkdownFeatureFlags(),
  }) {
    final theme = context.conduitTheme;
    final materialTheme = Theme.of(context);

    final bodyStyle = AppTypography.bodyMediumStyle.copyWith(
      color: theme.textPrimary,
      height: 1.45,
    );

    final codeColor = theme.code?.color ?? theme.textSecondary;

    final markdownThemeData = GptMarkdownThemeData(
      brightness: materialTheme.brightness,
      h1: AppTypography.headlineLargeStyle.copyWith(color: theme.textPrimary),
      h2: AppTypography.headlineMediumStyle.copyWith(color: theme.textPrimary),
      h3: AppTypography.headlineSmallStyle.copyWith(color: theme.textPrimary),
      h4: AppTypography.bodyLargeStyle.copyWith(color: theme.textPrimary),
      h5: AppTypography.bodyMediumStyle.copyWith(
        color: theme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      h6: AppTypography.bodySmallStyle.copyWith(color: theme.textSecondary),
      hrLineColor: theme.dividerColor,
      highlightColor: theme.surfaceContainer.withValues(alpha: 0.4),
      linkColor: materialTheme.colorScheme.primary,
      linkHoverColor: materialTheme.colorScheme.primary.withValues(alpha: 0.8),
    );

    return ConduitMarkdownTheme(
      textStyle: bodyStyle,
      themeData: markdownThemeData,
      imageBuilder: (context, imageUrl) {
        final uri = Uri.tryParse(imageUrl);
        if (uri == null) {
          return _buildImageError(context, context.conduitTheme);
        }

        final scheme = uri.scheme;

        if (scheme == 'data') {
          return buildBase64Image(imageUrl, context, context.conduitTheme);
        }

        if (scheme.isEmpty || scheme == 'http' || scheme == 'https') {
          return buildNetworkImage(imageUrl, context, context.conduitTheme);
        }

        return const SizedBox.shrink();
      },
      codeBuilder: (context, name, code, closed) {
        final conduitTheme = context.conduitTheme;
        final language = name.trim().isEmpty ? null : name.trim();
        final isMermaid =
            flags.enableMermaid && (language?.toLowerCase() == 'mermaid');

        if (isMermaid && !flags.enableMermaid) {
          return CodeBlockWrapper(
            code: code,
            language: language,
            theme: conduitTheme,
            closed: closed,
            child: _buildUnsupportedMermaidContainer(
              conduitTheme: conduitTheme,
              codeColor: codeColor,
              code: code,
            ),
          );
        }

        final Widget content;
        if (isMermaid) {
          content = MermaidDiagram.isSupported
              ? _buildMermaidContainer(
                  context: context,
                  conduitTheme: conduitTheme,
                  materialTheme: materialTheme,
                  code: code,
                )
              : _buildUnsupportedMermaidContainer(
                  conduitTheme: conduitTheme,
                  codeColor: codeColor,
                  code: code,
                );
        } else {
          content = _buildCodeContainer(
            context: context,
            conduitTheme: conduitTheme,
            codeColor: codeColor,
            code: code,
            language: language,
            enableHighlight: flags.enableSyntaxHighlighting,
          );
        }

        return CodeBlockWrapper(
          code: code,
          language: language,
          theme: conduitTheme,
          closed: closed,
          child: content,
        );
      },
    );
  }

  static Widget _buildCodeContainer({
    required BuildContext context,
    required ConduitThemeExtension conduitTheme,
    required Color codeColor,
    required String code,
    required String? language,
    required bool enableHighlight,
  }) {
    final textStyle = AppTypography.codeStyle.copyWith(
      color: conduitTheme.codeText,
      height: 1.55,
      fontSize: 13,
    );

    final highlightLanguage = _normalizeLanguage(language);
    final canHighlight = enableHighlight && highlightLanguage != null;

    final Widget baseChild;
    if (canHighlight) {
      final highlightTheme = _transparentHighlightTheme(
        atomOneDarkReasonableTheme,
      );
      baseChild = HighlightView(
        code,
        language: highlightLanguage,
        theme: highlightTheme,
        padding: EdgeInsets.zero,
        textStyle: textStyle,
      );
    } else {
      baseChild = SelectableText(
        code,
        maxLines: null,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        textWidthBasis: TextWidthBasis.parent,
        style: textStyle,
      );
    }

    return baseChild;
  }

  static Widget _buildMermaidContainer({
    required BuildContext context,
    required ConduitThemeExtension conduitTheme,
    required ThemeData materialTheme,
    required String code,
  }) {
    final tokens = context.colorTokens;
    return SizedBox(
      height: 360,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.sm),
        child: MermaidDiagram(
          code: code,
          brightness: materialTheme.brightness,
          colorScheme: materialTheme.colorScheme,
          tokens: tokens,
        ),
      ),
    );
  }

  static Widget _buildUnsupportedMermaidContainer({
    required ConduitThemeExtension conduitTheme,
    required Color codeColor,
    required String code,
  }) {
    final textStyle = AppTypography.bodySmallStyle.copyWith(
      color: conduitTheme.codeText.withValues(alpha: 0.7),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Mermaid preview is not available on this platform.',
          style: textStyle,
        ),
        const SizedBox(height: Spacing.xs),
        SelectableText(
          code,
          maxLines: null,
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
          textWidthBasis: TextWidthBasis.parent,
          style: AppTypography.codeStyle.copyWith(
            color: conduitTheme.code?.color ?? codeColor,
          ),
        ),
      ],
    );
  }

  static Map<String, TextStyle> _transparentHighlightTheme(
    Map<String, TextStyle> base,
  ) {
    final themed = Map<String, TextStyle>.from(base);
    final root = base['root'];
    themed['root'] = (root ?? const TextStyle()).copyWith(
      backgroundColor: Colors.transparent,
    );
    return themed;
  }

  static String? _normalizeLanguage(String? lang) {
    if (lang == null || lang.trim().isEmpty) {
      return null;
    }
    final value = lang.trim().toLowerCase();
    switch (value) {
      case 'js':
      case 'javascript':
        return 'javascript';
      case 'ts':
      case 'typescript':
        return 'typescript';
      case 'sh':
      case 'zsh':
      case 'bash':
      case 'shell':
        return 'bash';
      case 'yml':
        return 'yaml';
      case 'py':
      case 'python':
        return 'python';
      case 'rb':
      case 'ruby':
        return 'ruby';
      case 'kt':
      case 'kotlin':
        return 'kotlin';
      case 'java':
        return 'java';
      case 'c#':
      case 'cs':
      case 'csharp':
        return 'cs';
      case 'objc':
      case 'objectivec':
        return 'objectivec';
      case 'swift':
        return 'swift';
      case 'go':
      case 'golang':
        return 'go';
      case 'php':
        return 'php';
      case 'dart':
        return 'dart';
      case 'json':
        return 'json';
      case 'html':
        return 'xml';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'sql':
        return 'sql';
      default:
        return value;
    }
  }

  static Widget buildBase64Image(
    String dataUrl,
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    try {
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex == -1) {
        throw Exception('Invalid data URL format');
      }

      final base64String = dataUrl.substring(commaIndex + 1);
      final imageBytes = base64.decode(base64String);

      return Container(
        margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _buildImageError(context, theme);
            },
          ),
        ),
      );
    } catch (e) {
      return _buildImageError(context, theme);
    }
  }

  static Widget buildNetworkImage(
    String url,
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    return CachedNetworkImage(
      imageUrl: url,
      placeholder: (context, url) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.surfaceBackground.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: theme.loadingIndicator,
            strokeWidth: 2,
          ),
        ),
      ),
      errorWidget: (context, url, error) => _buildImageError(context, theme),
    );
  }

  static Widget _buildImageError(
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: theme.surfaceBackground.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: theme.error.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, color: theme.error, size: 32),
          const SizedBox(height: Spacing.xs),
          Text(
            AppLocalizations.of(context)!.failedToLoadImage(''),
            style: TextStyle(color: theme.error, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class CodeBlockWrapper extends StatefulWidget {
  const CodeBlockWrapper({
    super.key,
    required this.child,
    required this.code,
    this.language,
    required this.theme,
    required this.closed,
  });

  final Widget child;
  final String code;
  final String? language;
  final ConduitThemeExtension theme;
  final bool closed;

  @override
  State<CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends State<CodeBlockWrapper> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    if (!widget.closed || widget.code.trim().isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() {
      _copied = true;
    });

    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _copied = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final conduitTheme = widget.theme;
    final canCopy = widget.closed && widget.code.trim().isNotEmpty;
    final icon = _copied
        ? Icons.check
        : canCopy
        ? Icons.copy
        : Icons.hourglass_empty;

    final background = conduitTheme.codeBackground;
    final borderColor = conduitTheme.codeBorder.withValues(alpha: 0.6);
    final headerColor = conduitTheme.codeAccent.withValues(alpha: 0.85);

    final languageLabel = (widget.language?.isNotEmpty ?? false)
        ? widget.language!
        : 'code';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        boxShadow: ConduitShadows.medium(context),
        border: Border.all(color: borderColor, width: BorderWidth.micro),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: headerColor,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    languageLabel,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: conduitTheme.codeText.withValues(alpha: 0.85),
                      fontFamily: AppTypography.monospaceFontFamily,
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: canCopy
                        ? (_copied
                              ? 'Copied'
                              : MaterialLocalizations.of(
                                  context,
                                ).copyButtonLabel)
                        : 'Copy available after generation completes',
                    child: IconButton(
                      onPressed: canCopy ? _handleCopy : null,
                      icon: Icon(icon, size: IconSize.sm),
                      color: canCopy
                          ? conduitTheme.codeText
                          : conduitTheme.codeText.withValues(alpha: 0.5),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(Spacing.xs),
                      style: IconButton.styleFrom(
                        backgroundColor: conduitTheme.codeText.withValues(
                          alpha: canCopy ? 0.08 : 0.04,
                        ),
                        disabledBackgroundColor: conduitTheme.codeText
                            .withValues(alpha: 0.03),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: background,
              padding: const EdgeInsets.all(Spacing.sm),
              child: DefaultTextStyle.merge(
                style: AppTypography.codeStyle.copyWith(
                  color: conduitTheme.codeText,
                ),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MermaidDiagram extends StatefulWidget {
  const MermaidDiagram({
    super.key,
    required this.code,
    required this.brightness,
    required this.colorScheme,
    required this.tokens,
  });

  final String code;
  final Brightness brightness;
  final ColorScheme colorScheme;
  final AppColorTokens tokens;

  static bool get isSupported => !kIsWeb;

  static Future<String> _loadScript() {
    return _scriptFuture ??= rootBundle.loadString('assets/mermaid.min.js');
  }

  static Future<String>? _scriptFuture;

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  WebViewController? _controller;
  String? _script;
  final Set<Factory<OneSequenceGestureRecognizer>> _gestureRecognizers =
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      };

  @override
  void initState() {
    super.initState();
    if (!MermaidDiagram.isSupported) {
      return;
    }
    MermaidDiagram._loadScript().then((value) {
      if (!mounted) {
        return;
      }
      _script = value;
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent);
      _loadHtml();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null || _script == null) {
      return;
    }
    final codeChanged = oldWidget.code != widget.code;
    final themeChanged =
        oldWidget.brightness != widget.brightness ||
        oldWidget.colorScheme != widget.colorScheme ||
        oldWidget.tokens != widget.tokens;
    if (codeChanged || themeChanged) {
      _loadHtml();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox.expand(
      child: WebViewWidget(
        controller: _controller!,
        gestureRecognizers: _gestureRecognizers,
      ),
    );
  }

  void _loadHtml() {
    if (_controller == null || _script == null) {
      return;
    }
    _controller!.loadHtmlString(_buildHtml(widget.code, _script!));
  }

  String _buildHtml(String code, String script) {
    final theme = widget.brightness == Brightness.dark ? 'dark' : 'default';
    final encoded = jsonEncode(code);
    final primary = _toHex(widget.tokens.brandTone60);
    final secondary = _toHex(widget.tokens.accentTeal60);
    final background = _toHex(widget.tokens.codeBackground);
    final onBackground = _toHex(widget.tokens.codeText);
    final lineColor = _toHex(widget.tokens.codeAccent);
    final errorColor = _toHex(widget.tokens.statusError60);

    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
      html, body { margin: 0; padding: 0; background: transparent; }
      body { color: $onBackground; font-family: -apple-system, sans-serif; }
      #diagram { padding: 8px; overflow: auto; }
      svg { height: auto; display: block; }
    </style>
    <script type="text/javascript">
$script
    </script>
  </head>
  <body>
    <div id="diagram"></div>
    <script type="text/javascript">
      const graphDefinition = $encoded;
      const themeConfig = {
        startOnLoad: false,
        theme: '$theme',
        securityLevel: 'loose',
        themeVariables: {
          primaryColor: '$primary',
          secondaryColor: '$secondary',
          background: '$background',
          textColor: '$onBackground',
          lineColor: '$lineColor'
        }
      };

      (async () => {
        const target = document.getElementById('diagram');
        try {
          mermaid.initialize(themeConfig);
          const { svg, bindFunctions } = await mermaid.render('graphDiv', graphDefinition);
          target.innerHTML = svg;
          if (typeof bindFunctions === 'function') {
            bindFunctions(target);
          }
        } catch (error) {
          target.innerHTML = '<pre style="color:$errorColor">' + String(error) + '</pre>';
          console.error('Mermaid render failed', error);
        }
      })();
    </script>
  </body>
</html>
''';
  }

  String _toHex(Color color) {
    final value = color.toARGB32();
    return '#'
            '${((value >> 16) & 0xFF).toRadixString(16).padLeft(2, '0')}'
            '${((value >> 8) & 0xFF).toRadixString(16).padLeft(2, '0')}'
            '${(value & 0xFF).toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}
