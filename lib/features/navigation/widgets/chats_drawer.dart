import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../chat/providers/chat_providers.dart' as chat;
// import '../../files/views/files_page.dart';
import '../../../core/utils/debug_logger.dart';
import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import 'package:eden_ai/l10n/app_localizations.dart';
import '../../../core/utils/user_display_name.dart';
import '../../../core/utils/model_icon_utils.dart';
import '../../auth/providers/unified_auth_providers.dart';
import '../../../core/utils/user_avatar_utils.dart';
import '../../../shared/utils/conversation_context_menu.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/widgets/model_avatar.dart';
import '../../../core/models/model.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/folder.dart';

class ChatsDrawer extends ConsumerStatefulWidget {
  const ChatsDrawer({super.key});

  @override
  ConsumerState<ChatsDrawer> createState() => _ChatsDrawerState();
}

class _ChatsDrawerState extends ConsumerState<ChatsDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'drawer_search');
  final ScrollController _listController = ScrollController();
  Timer? _debounce;
  String _query = '';
  bool _isLoadingConversation = false;
  String? _pendingConversationId;
  String? _dragHoverFolderId;
  bool _isDragging = false;
  bool _draggingHasFolder = false;

  // UI state providers for sections
  static final _showArchivedProvider =
      NotifierProvider<_ShowArchivedNotifier, bool>(_ShowArchivedNotifier.new);
  static final _expandedFoldersProvider =
      NotifierProvider<_ExpandedFoldersNotifier, Map<String, bool>>(
        _ExpandedFoldersNotifier.new,
      );

  Future<void> _refreshChats() async {
    try {
      // Always refresh folders and conversations cache
      refreshConversationsCache(ref, includeFolders: true);

      if (_query.trim().isEmpty) {
        // Refresh main conversations list
        try {
          await ref.read(conversationsProvider.future);
        } catch (_) {}
      } else {
        // Refresh server-side search results
        ref.invalidate(serverSearchProvider(_query));
        try {
          await ref.read(serverSearchProvider(_query).future);
        } catch (_) {}
      }

      // Await folders as well so the list stabilizes
      try {
        await ref.read(foldersProvider.future);
      } catch (_) {}
    } catch (_) {}
  }

  Widget _buildRefreshableScrollable({required List<Widget> children}) {
    // Common padding used in both scrollable variants
    const padding = EdgeInsets.fromLTRB(0, Spacing.sm, 0, Spacing.md);

    if (Platform.isIOS) {
      // Use Cupertino-style pull-to-refresh on iOS
      final scroll = CustomScrollView(
        key: const PageStorageKey<String>('chats_drawer_scroll'),
        controller: _listController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refreshChats),
          SliverPadding(
            padding: padding,
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      );
      return CupertinoScrollbar(controller: _listController, child: scroll);
    }

    // Material pull-to-refresh elsewhere
    return RefreshIndicator(
      onRefresh: _refreshChats,
      child: Scrollbar(
        controller: _listController,
        child: ListView(
          key: const PageStorageKey<String>('chats_drawer_scroll'),
          controller: _listController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: children,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = _searchController.text.trim());
    });
  }

  // Payload for drag-and-drop of conversations
  // Kept local to this widget
  // ignore: unused_element
  static _DragConversationData _dragData(String id, String title) =>
      _DragConversationData(id: id, title: title);

  @override
  Widget build(BuildContext context) {
    // Bottom section now only shows navigation actions
    final theme = context.conduitTheme;

    return Container(
      color: theme.surfaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.inputPadding,
              Spacing.sm,
              Spacing.md,
              Spacing.sm,
            ),
            child: Row(children: [Expanded(child: _buildSearchField(context))]),
          ),
          Expanded(child: _buildConversationList(context)),
          Divider(height: 1, color: theme.dividerColor),
          _buildBottomSection(context),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = context.conduitTheme;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (_) => _onSearchChanged(),
      style: AppTypography.standard.copyWith(color: theme.inputText),
      decoration: InputDecoration(
        isDense: true,
        hintText: AppLocalizations.of(context)!.searchConversations,
        hintStyle: AppTypography.standard.copyWith(
          color: theme.inputPlaceholder,
        ),
        prefixIcon: Icon(
          Platform.isIOS ? CupertinoIcons.search : Icons.search,
          color: theme.iconSecondary,
          size: IconSize.input,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: TouchTarget.minimum,
          minHeight: TouchTarget.minimum,
        ),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                  _searchFocusNode.unfocus();
                },
                icon: Icon(
                  Platform.isIOS
                      ? CupertinoIcons.clear_circled_solid
                      : Icons.clear,
                  color: theme.iconSecondary,
                  size: IconSize.input,
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
          minWidth: TouchTarget.minimum,
          minHeight: TouchTarget.minimum,
        ),
        filled: true,
        fillColor: theme.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide(color: theme.inputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide(color: theme.buttonPrimary, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
      ),
    );
  }

  Widget _buildConversationList(BuildContext context) {
    final theme = context.conduitTheme;

    if (_query.isEmpty) {
      final conversationsAsync = ref.watch(conversationsProvider);
      return conversationsAsync.when(
        data: (items) {
          final list = items;

          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Text(
                  AppLocalizations.of(context)!.noConversationsYet,
                  style: AppTypography.bodyMediumStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ),
            );
          }

          // Build sections
          final pinned = list.where((c) => c.pinned == true).toList();

          // Determine which folder IDs actually exist from the API
          final foldersState = ref.watch(foldersProvider);
          final availableFolderIds = foldersState.maybeWhen(
            data: (folders) => folders.map((f) => f.id).toSet(),
            orElse: () => <String>{},
          );

          // Conversations that reference a non-existent/unknown folder should not disappear.
          // Treat those as regular until the folders list is available and contains the ID.
          final regular = list.where((c) {
            final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
            final folderKnown =
                hasFolder && availableFolderIds.contains(c.folderId);
            return c.pinned != true &&
                c.archived != true &&
                (!hasFolder || !folderKnown);
          }).toList();

          final foldered = list.where((c) {
            final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
            return c.pinned != true &&
                c.archived != true &&
                hasFolder &&
                availableFolderIds.contains(c.folderId);
          }).toList();

          final archived = list.where((c) => c.archived == true).toList();

          final children = <Widget>[
            if (pinned.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(
                  left: Spacing.md,
                  right: Spacing.md,
                ),
                child: _buildSectionHeader(
                  AppLocalizations.of(context)!.pinned,
                  pinned.length,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              ...pinned.map((conv) => _buildTileFor(conv)),
              const SizedBox(height: Spacing.md),
            ],

            // Folders section (shown even if empty)
            Padding(
              padding: const EdgeInsets.only(
                left: Spacing.md,
                right: Spacing.md,
              ),
              child: _buildFoldersSectionHeader(),
            ),
            const SizedBox(height: Spacing.xs),
            if (_isDragging && _draggingHasFolder) ...[
              _buildUnfileDropTarget(),
              const SizedBox(height: Spacing.sm),
            ],
            ...ref
                .watch(foldersProvider)
                .when(
                  data: (folders) {
                    final grouped = <String, List<dynamic>>{};
                    for (final c in foldered) {
                      final id = c.folderId!;
                      grouped.putIfAbsent(id, () => []).add(c);
                    }

                    final expandedMap = ref.watch(_expandedFoldersProvider);

                    // Show all folders (including empty)
                    final sections = folders.map((folder) {
                      final existing = grouped[folder.id] ?? const <dynamic>[];
                      final convs = _resolveFolderConversations(
                        folder,
                        existing,
                      );
                      final isExpanded =
                          expandedMap[folder.id] ?? folder.isExpanded;
                      final hasItems = convs.isNotEmpty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildFolderHeader(
                            folder.id,
                            folder.name,
                            convs.length,
                            defaultExpanded: folder.isExpanded,
                          ),
                          if (isExpanded && hasItems) ...[
                            const SizedBox(height: Spacing.xs),
                            ...convs.map(
                              (c) => _buildTileFor(c, inFolder: true),
                            ),
                            const SizedBox(height: Spacing.xs),
                          ],
                          const SizedBox(height: Spacing.xs),
                        ],
                      );
                    }).toList();
                    return sections.isEmpty
                        ? [const SizedBox.shrink()]
                        : sections;
                  },
                  loading: () => [const SizedBox.shrink()],
                  error: (e, st) => [const SizedBox.shrink()],
                ),
            const SizedBox(height: Spacing.md),

            if (regular.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(
                  left: Spacing.md,
                  right: Spacing.md,
                ),
                child: _buildSectionHeader(
                  AppLocalizations.of(context)!.recent,
                  regular.length,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              ...regular.map(_buildTileFor),
            ],

            if (archived.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: _buildArchivedSection(archived),
              ),
            ],
          ];
          return _buildRefreshableScrollable(children: children);
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text(
              AppLocalizations.of(context)!.failedToLoadChats,
              style: AppTypography.bodyMediumStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    // Server-backed search
    final searchAsync = ref.watch(serverSearchProvider(_query));
    return searchAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                'No results for "$_query"',
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
          );
        }

        final pinned = list.where((c) => c.pinned == true).toList();

        // For search results, apply the same folder safety logic
        final foldersState = ref.watch(foldersProvider);
        final availableFolderIds = foldersState.maybeWhen(
          data: (folders) => folders.map((f) => f.id).toSet(),
          orElse: () => <String>{},
        );

        final regular = list.where((c) {
          final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
          final folderKnown =
              hasFolder && availableFolderIds.contains(c.folderId);
          return c.pinned != true &&
              c.archived != true &&
              (!hasFolder || !folderKnown);
        }).toList();

        final foldered = list.where((c) {
          final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
          return c.pinned != true &&
              c.archived != true &&
              hasFolder &&
              availableFolderIds.contains(c.folderId);
        }).toList();

        final archived = list.where((c) => c.archived == true).toList();

        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: Spacing.md, right: Spacing.md),
            child: _buildSectionHeader('Results', list.length),
          ),
          const SizedBox(height: Spacing.xs),
          if (pinned.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildSectionHeader(
                AppLocalizations.of(context)!.pinned,
                pinned.length,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            ...pinned.map((conv) => _buildTileFor(conv)),
            const SizedBox(height: Spacing.md),
          ],
          // Folders section (shown even if empty)
          Padding(
            padding: const EdgeInsets.only(left: Spacing.md, right: Spacing.md),
            child: _buildFoldersSectionHeader(),
          ),
          const SizedBox(height: Spacing.xs),
          if (_isDragging && _draggingHasFolder) ...[
            _buildUnfileDropTarget(),
            const SizedBox(height: Spacing.sm),
          ],
          ...ref
              .watch(foldersProvider)
              .when(
                data: (folders) {
                  final grouped = <String, List<dynamic>>{};
                  for (final c in foldered) {
                    final id = c.folderId!;
                    grouped.putIfAbsent(id, () => []).add(c);
                  }

                  final expandedMap = ref.watch(_expandedFoldersProvider);

                  final sections = folders.map((folder) {
                    final existing = grouped[folder.id] ?? const <dynamic>[];
                    final convs = _resolveFolderConversations(folder, existing);
                    final isExpanded =
                        expandedMap[folder.id] ?? folder.isExpanded;
                    final hasItems = convs.isNotEmpty;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFolderHeader(
                          folder.id,
                          folder.name,
                          convs.length,
                          defaultExpanded: folder.isExpanded,
                        ),
                        if (isExpanded && hasItems) ...[
                          const SizedBox(height: Spacing.xs),
                          ...convs.map((c) => _buildTileFor(c, inFolder: true)),
                          const SizedBox(height: Spacing.sm),
                        ],
                      ],
                    );
                  }).toList();
                  return sections.isEmpty
                      ? [const SizedBox.shrink()]
                      : sections;
                },
                loading: () => [const SizedBox.shrink()],
                error: (e, st) => [const SizedBox.shrink()],
              ),
          const SizedBox(height: Spacing.md),
          if (regular.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildSectionHeader(
                AppLocalizations.of(context)!.recent,
                regular.length,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            ...regular.map(_buildTileFor),
          ],
          if (archived.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildArchivedSection(archived),
            ),
          ],
        ];
        return _buildRefreshableScrollable(children: children);
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Text(
            'Search failed',
            style: AppTypography.bodyMediumStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    final theme = context.conduitTheme;
    return Row(
      children: [
        Text(
          title,
          style: AppTypography.labelStyle.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(width: Spacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.surfaceContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppBorderRadius.xs),
            border: Border.all(
              color: theme.dividerColor,
              width: BorderWidth.thin,
            ),
          ),
          child: Text(
            '$count',
            style: AppTypography.tiny.copyWith(color: theme.textSecondary),
          ),
        ),
      ],
    );
  }

  /// Header for the Folders section with a create button on the right
  Widget _buildFoldersSectionHeader() {
    final theme = context.conduitTheme;
    return Row(
      children: [
        Text(
          AppLocalizations.of(context)!.folders,
          style: AppTypography.labelStyle.copyWith(color: theme.textSecondary),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: AppLocalizations.of(context)!.newFolder,
          icon: Icon(
            Platform.isIOS
                ? CupertinoIcons.folder_badge_plus
                : Icons.create_new_folder_outlined,
            color: theme.iconPrimary,
          ),
          onPressed: _promptCreateFolder,
        ),
      ],
    );
  }

  Future<void> _promptCreateFolder() async {
    final name = await ThemedDialogs.promptTextInput(
      context,
      title: AppLocalizations.of(context)!.newFolder,
      hintText: AppLocalizations.of(context)!.folderName,
      confirmText: AppLocalizations.of(context)!.create,
      cancelText: AppLocalizations.of(context)!.cancel,
    );

    if (name == null) return;
    if (name.isEmpty) return;
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.createFolder(name: name);
      HapticFeedback.lightImpact();
      refreshConversationsCache(ref, includeFolders: true);
    } catch (e, stackTrace) {
      if (!mounted) return;
      DebugLogger.error(
        'create-folder-failed',
        scope: 'drawer',
        error: e,
        stackTrace: stackTrace,
      );
      await _showDrawerError(
        AppLocalizations.of(context)!.failedToCreateFolder,
      );
    }
  }

  Widget _buildFolderHeader(
    String folderId,
    String name,
    int count, {
    bool defaultExpanded = false,
  }) {
    final theme = context.conduitTheme;
    final expandedMap = ref.watch(_expandedFoldersProvider);
    final isExpanded = expandedMap[folderId] ?? defaultExpanded;
    final isHover = _dragHoverFolderId == folderId;
    return DragTarget<_DragConversationData>(
      onWillAcceptWithDetails: (details) {
        setState(() => _dragHoverFolderId = folderId);
        return true;
      },
      onLeave: (_) => setState(() => _dragHoverFolderId = null),
      onAcceptWithDetails: (details) async {
        setState(() {
          _dragHoverFolderId = null;
          _isDragging = false;
        });
        try {
          final api = ref.read(apiServiceProvider);
          if (api == null) throw Exception('No API service');
          await api.moveConversationToFolder(details.data.id, folderId);
          HapticFeedback.selectionClick();
          refreshConversationsCache(ref, includeFolders: true);
        } catch (e, stackTrace) {
          DebugLogger.error(
            'move-conversation-failed',
            scope: 'drawer',
            error: e,
            stackTrace: stackTrace,
          );
          if (mounted) {
            await _showDrawerError(
              AppLocalizations.of(context)!.failedToMoveChat,
            );
          }
        }
      },
      builder: (context, candidateData, rejectedData) {
        final baseColor = theme.surfaceContainer;
        final hoverColor = theme.buttonPrimary.withValues(alpha: 0.08);
        final borderColor = isHover
            ? theme.buttonPrimary.withValues(alpha: 0.60)
            : theme.surfaceContainerHighest.withValues(alpha: 0.40);

        Color? overlayForStates(Set<WidgetState> states) {
          if (states.contains(WidgetState.pressed)) {
            return theme.buttonPrimary.withValues(alpha: Alpha.buttonPressed);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return theme.buttonPrimary.withValues(alpha: Alpha.hover);
          }
          return Colors.transparent;
        }

        return Material(
          color: isHover ? hoverColor : baseColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: borderColor, width: BorderWidth.thin),
          ),
          child: InkWell(
            borderRadius: BorderRadius.zero,
            onTap: () {
              final current = {...ref.read(_expandedFoldersProvider)};
              final next = !isExpanded;
              current[folderId] = next;
              ref.read(_expandedFoldersProvider.notifier).set(current);
            },
            onLongPress: () {
              HapticFeedback.selectionClick();
              _showFolderContextMenu(context, folderId, name);
            },
            overlayColor: WidgetStateProperty.resolveWith(overlayForStates),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TouchTarget.listItem,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hasFiniteWidth = constraints.maxWidth.isFinite;
                    final textFit = hasFiniteWidth
                        ? FlexFit.tight
                        : FlexFit.loose;

                    return Row(
                      mainAxisSize: hasFiniteWidth
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      children: [
                        Icon(
                          isExpanded
                              ? (Platform.isIOS
                                    ? CupertinoIcons.folder_open
                                    : Icons.folder_open)
                              : (Platform.isIOS
                                    ? CupertinoIcons.folder
                                    : Icons.folder),
                          color: theme.iconPrimary,
                          size: IconSize.listItem,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Flexible(
                          fit: textFit,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.standard.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(
                          '$count',
                          style: AppTypography.standard.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Icon(
                          isExpanded
                              ? (Platform.isIOS
                                    ? CupertinoIcons.chevron_up
                                    : Icons.expand_less)
                              : (Platform.isIOS
                                    ? CupertinoIcons.chevron_down
                                    : Icons.expand_more),
                          color: theme.iconSecondary,
                          size: IconSize.listItem,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<dynamic> _resolveFolderConversations(
    Folder folder,
    List<dynamic> existing,
  ) {
    // Preserve the current conversational ordering while ensuring items from
    // the folder metadata appear even if the main list has not fetched them
    // yet. This primarily happens when chats live exclusively inside folders
    // and the conversations endpoint omits them.
    final result = <dynamic>[];

    final existingMap = <String, dynamic>{};
    for (final item in existing) {
      final id = _conversationId(item);
      if (id != null) {
        existingMap[id] = item;
      }
    }

    if (folder.conversationIds.isNotEmpty) {
      for (final convId in folder.conversationIds) {
        final existingItem = existingMap.remove(convId);
        if (existingItem != null) {
          result.add(existingItem);
        } else {
          result.add(_placeholderConversation(convId, folder.id));
        }
      }

      // Append any remaining conversations that claim this folder but are
      // missing from the folder metadata list (defensive for API drift).
      result.addAll(existingMap.values);
    } else {
      result.addAll(existingMap.values);
    }

    return result;
  }

  Conversation _placeholderConversation(
    String conversationId,
    String folderId,
  ) {
    const fallbackTitle = 'Chat';
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return Conversation(
      id: conversationId,
      title: fallbackTitle,
      createdAt: epoch,
      updatedAt: epoch,
      folderId: folderId,
      messages: const [],
    );
  }

  String? _conversationId(dynamic item) {
    if (item is Conversation) return item.id;
    try {
      final value = (item as dynamic).id;
      if (value is String) {
        return value;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _showDrawerError(String message) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final theme = context.conduitTheme;
    await ThemedDialogs.show<void>(
      context,
      title: l10n.errorMessage,
      content: Text(
        message,
        style: AppTypography.bodyMediumStyle.copyWith(
          color: theme.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.ok),
        ),
      ],
    );
  }

  void _showFolderContextMenu(
    BuildContext context,
    String folderId,
    String folderName,
  ) {
    final l10n = AppLocalizations.of(context)!;

    showConduitContextMenu(
      context: context,
      actions: [
        ConduitContextMenuAction(
          cupertinoIcon: CupertinoIcons.pencil,
          materialIcon: Icons.edit_rounded,
          label: l10n.rename,
          onBeforeClose: () => HapticFeedback.selectionClick(),
          onSelected: () async {
            await _renameFolder(context, folderId, folderName);
          },
        ),
        ConduitContextMenuAction(
          cupertinoIcon: CupertinoIcons.delete,
          materialIcon: Icons.delete_rounded,
          label: l10n.delete,
          destructive: true,
          onBeforeClose: () => HapticFeedback.mediumImpact(),
          onSelected: () async {
            await _confirmAndDeleteFolder(context, folderId, folderName);
          },
        ),
      ],
    );
  }

  Future<void> _renameFolder(
    BuildContext context,
    String folderId,
    String currentName,
  ) async {
    final newName = await ThemedDialogs.promptTextInput(
      context,
      title: AppLocalizations.of(context)!.rename,
      hintText: AppLocalizations.of(context)!.folderName,
      initialValue: currentName,
      confirmText: AppLocalizations.of(context)!.save,
      cancelText: AppLocalizations.of(context)!.cancel,
    );

    if (newName == null) return;
    if (newName.isEmpty || newName == currentName) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.updateFolder(folderId, name: newName);
      HapticFeedback.selectionClick();
      refreshConversationsCache(ref, includeFolders: true);
    } catch (e, stackTrace) {
      if (!mounted) return;
      DebugLogger.error(
        'rename-folder-failed',
        scope: 'drawer',
        error: e,
        stackTrace: stackTrace,
      );
      await _showDrawerError('Failed to rename folder');
    }
  }

  Future<void> _confirmAndDeleteFolder(
    BuildContext context,
    String folderId,
    String folderName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: l10n.deleteFolderTitle,
      message: l10n.deleteFolderMessage,
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!mounted) return;
    if (!confirmed) return;

    final deleteFolderError = l10n.failedToDeleteFolder;
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.deleteFolder(folderId);
      HapticFeedback.mediumImpact();
      refreshConversationsCache(ref, includeFolders: true);
    } catch (e, stackTrace) {
      if (!mounted) return;
      DebugLogger.error(
        'delete-folder-failed',
        scope: 'drawer',
        error: e,
        stackTrace: stackTrace,
      );
      await _showDrawerError(deleteFolderError);
    }
  }

  Widget _buildUnfileDropTarget() {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final isHover = _dragHoverFolderId == '__UNFILE__';
    return DragTarget<_DragConversationData>(
      onWillAcceptWithDetails: (details) {
        setState(() => _dragHoverFolderId = '__UNFILE__');
        return true;
      },
      onLeave: (_) => setState(() => _dragHoverFolderId = null),
      onAcceptWithDetails: (details) async {
        setState(() {
          _dragHoverFolderId = null;
          _isDragging = false;
        });
        try {
          final api = ref.read(apiServiceProvider);
          if (api == null) throw Exception('No API service');
          await api.moveConversationToFolder(details.data.id, null);
          HapticFeedback.selectionClick();
          refreshConversationsCache(ref, includeFolders: true);
        } catch (e, stackTrace) {
          DebugLogger.error(
            'unfile-conversation-failed',
            scope: 'drawer',
            error: e,
            stackTrace: stackTrace,
          );
          if (mounted) {
            await _showDrawerError(l10n.failedToMoveChat);
          }
        }
      },
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: isHover
                ? theme.buttonPrimary.withValues(alpha: 0.08)
                : theme.surfaceContainer.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            border: Border.all(
              color: isHover
                  ? theme.buttonPrimary.withValues(alpha: 0.6)
                  : theme.dividerColor,
              width: BorderWidth.regular,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Platform.isIOS
                    ? CupertinoIcons.folder_badge_minus
                    : Icons.folder_off_outlined,
                color: theme.iconPrimary,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Drop here to remove from folder',
                  style: AppTypography.bodyMediumStyle.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTileFor(dynamic conv, {bool inFolder = false}) {
    final isActive = ref.watch(activeConversationProvider)?.id == conv.id;
    final title = conv.title?.isEmpty == true ? 'Chat' : (conv.title ?? 'Chat');
    final theme = context.conduitTheme;
    final bool isLoadingSelected =
        (_pendingConversationId == conv.id) &&
        (ref.watch(chat.isLoadingConversationProvider) == true);
    final bool isPinned = conv.pinned == true;

    Model? model;
    final modelId = (conv.model is String && (conv.model as String).isNotEmpty)
        ? conv.model as String
        : null;
    if (modelId != null) {
      final modelsAsync = ref.watch(modelsProvider);
      model = modelsAsync.maybeWhen(
        data: (models) {
          for (final m in models) {
            if (m.id == modelId) return m;
          }
          return null;
        },
        orElse: () => null,
      );
    }

    final api = ref.watch(apiServiceProvider);
    final modelIconUrl = resolveModelIconUrlForModel(api, model);

    Widget? leading;
    if (modelId != null) {
      leading = ModelAvatar(
        size: 28,
        imageUrl: modelIconUrl,
        label: model?.name ?? modelId,
      );
    }

    final tile = _ConversationTile(
      title: title,
      pinned: isPinned,
      selected: isActive,
      isLoading: isLoadingSelected,
      leading: leading,
      onTap: _isLoadingConversation
          ? null
          : () => _selectConversation(context, conv.id),
      onLongPress: null,
      onMorePressed: () {
        showConversationContextMenu(
          context: context,
          ref: ref,
          conversation: conv,
        );
      },
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: Spacing.xs,
        left: inFolder ? Spacing.md : 0,
      ),
      child: LongPressDraggable<_DragConversationData>(
        data: _DragConversationData(id: conv.id, title: title),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _ConversationDragFeedback(
          title: title,
          pinned: isPinned,
          theme: theme,
        ),
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: IgnorePointer(child: tile),
        ),
        onDragStarted: () {
          HapticFeedback.lightImpact();
          final hasFolder =
              (conv.folderId != null && (conv.folderId as String).isNotEmpty);
          setState(() {
            _isDragging = true;
            _draggingHasFolder = hasFolder;
          });
        },
        onDragEnd: (_) => setState(() {
          _dragHoverFolderId = null;
          _isDragging = false;
          _draggingHasFolder = false;
        }),
        child: tile,
      ),
    );
  }

  Widget _buildArchivedSection(List<dynamic> archived) {
    final theme = context.conduitTheme;
    final show = ref.watch(_showArchivedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: show
              ? theme.navigationSelectedBackground
              : theme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(
              color: show
                  ? theme.navigationSelected
                  : theme.surfaceContainerHighest.withValues(alpha: 0.40),
              width: BorderWidth.thin,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.zero,
            onTap: () => ref.read(_showArchivedProvider.notifier).set(!show),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return theme.buttonPrimary.withValues(
                  alpha: Alpha.buttonPressed,
                );
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return theme.buttonPrimary.withValues(alpha: Alpha.hover);
              }
              return Colors.transparent;
            }),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TouchTarget.listItem,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hasFiniteWidth = constraints.maxWidth.isFinite;
                    final textFit = hasFiniteWidth
                        ? FlexFit.tight
                        : FlexFit.loose;

                    return Row(
                      mainAxisSize: hasFiniteWidth
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      children: [
                        Icon(
                          Platform.isIOS
                              ? CupertinoIcons.archivebox
                              : Icons.archive_rounded,
                          color: theme.iconPrimary,
                          size: IconSize.listItem,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Flexible(
                          fit: textFit,
                          child: Text(
                            AppLocalizations.of(context)!.archived,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.standard.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(
                          '${archived.length}',
                          style: AppTypography.standard.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Icon(
                          show
                              ? (Platform.isIOS
                                    ? CupertinoIcons.chevron_up
                                    : Icons.expand_less)
                              : (Platform.isIOS
                                    ? CupertinoIcons.chevron_down
                                    : Icons.expand_more),
                          color: theme.iconSecondary,
                          size: IconSize.listItem,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (show) ...[
          const SizedBox(height: Spacing.xs),
          ...archived.map((c) => _buildTileFor(c)),
        ],
      ],
    );
  }

  Future<void> _selectConversation(BuildContext context, String id) async {
    if (_isLoadingConversation) return;
    setState(() => _isLoadingConversation = true);
    final navigator = Navigator.of(context);
    // Capture a provider container detached from this widget's lifecycle so
    // we can continue to read/write providers after the drawer is closed.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      // Mark global loading to show skeletons in chat
      container.read(chat.isLoadingConversationProvider.notifier).set(true);
      _pendingConversationId = id;

      // Immediately clear current chat to show loading skeleton in the chat view
      container.read(activeConversationProvider.notifier).clear();
      container.read(chat.chatMessagesProvider.notifier).clearMessages();

      // Close the drawer immediately for faster perceived performance
      if (mounted) {
        // Prefer closing the Scaffold's drawer to avoid popping other routes
        final scaffold = Scaffold.maybeOf(context);
        if (scaffold?.isDrawerOpen == true) {
          scaffold!.closeDrawer();
        } else {
          navigator.maybePop();
        }
      }

      // Load the full conversation details in the background
      final api = container.read(apiServiceProvider);
      if (api != null) {
        final full = await api.getConversation(id);
        container.read(activeConversationProvider.notifier).set(full);
      } else {
        // Fallback: use the lightweight item to update the active conversation
        container
            .read(activeConversationProvider.notifier)
            .set(
              (await container.read(
                conversationsProvider.future,
              )).firstWhere((c) => c.id == id),
            );
      }

      // Clear loading after data is ready
      container.read(chat.isLoadingConversationProvider.notifier).set(false);
      _pendingConversationId = null;
    } catch (_) {
      container.read(chat.isLoadingConversationProvider.notifier).set(false);
      _pendingConversationId = null;
    } finally {
      if (mounted) setState(() => _isLoadingConversation = false);
    }
  }

  Widget _buildBottomSection(BuildContext context) {
    final theme = context.conduitTheme;
    final currentUserAsync = ref.watch(currentUserProvider);
    final userFromProfile = currentUserAsync.maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    final authUser = ref.watch(currentUserProvider2);
    final user = userFromProfile ?? authUser;
    final api = ref.watch(apiServiceProvider);

    String initialFor(String name) {
      if (name.isEmpty) return 'U';
      final ch = name.characters.first;
      return ch.toUpperCase();
    }

    final displayName = deriveUserDisplayName(user);
    final initial = initialFor(displayName);
    final avatarUrl = resolveUserAvatarUrlForUser(api, user);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user != null) ...[
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: theme.surfaceContainer.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppBorderRadius.md),
                border: Border.all(
                  color: theme.dividerColor,
                  width: BorderWidth.regular,
                ),
                boxShadow: ConduitShadows.card(context),
              ),
              child: Row(
                children: [
                  Container(
                    width: IconSize.xl,
                    height: IconSize.xl,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.avatar,
                      ),
                      border: Border.all(
                        color: theme.buttonPrimary.withValues(alpha: 0.35),
                        width: BorderWidth.thin,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: UserAvatar(
                      size: IconSize.xl,
                      imageUrl: avatarUrl,
                      fallbackText: initial,
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmallStyle.copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.manage,
                    onPressed: () {
                      Navigator.of(context).maybePop();
                      context.pushNamed(RouteNames.profile);
                    },
                    icon: Icon(
                      Platform.isIOS
                          ? CupertinoIcons.settings
                          : Icons.settings_rounded,
                      color: theme.iconSecondary,
                      size: IconSize.listItem,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShowArchivedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class _ExpandedFoldersNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => {};

  void set(Map<String, bool> value) => state = Map<String, bool>.from(value);
}

class _DragConversationData {
  final String id;
  final String title;
  const _DragConversationData({required this.id, required this.title});
}

class _ConversationDragFeedback extends StatelessWidget {
  final String title;
  final bool pinned;
  final ConduitThemeExtension theme;

  const _ConversationDragFeedback({
    required this.title,
    required this.pinned,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.zero;
    final borderColor = theme.surfaceContainerHighest.withValues(alpha: 0.40);

    return Material(
      color: Colors.transparent,
      elevation: Elevation.low,
      borderRadius: borderRadius,
      child: Container(
        constraints: const BoxConstraints(minHeight: TouchTarget.listItem),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: theme.surfaceContainer,
          borderRadius: borderRadius,
          border: Border.all(color: borderColor, width: BorderWidth.thin),
        ),
        child: _ConversationTileContent(
          title: title,
          pinned: pinned,
          selected: false,
          isLoading: false,
          onMorePressed: null,
        ),
      ),
    );
  }
}

class _ConversationTileContent extends StatelessWidget {
  final String title;
  final bool pinned;
  final bool selected;
  final bool isLoading;
  final VoidCallback? onMorePressed;
  final Widget? leading;

  const _ConversationTileContent({
    required this.title,
    required this.pinned,
    required this.selected,
    required this.isLoading,
    this.onMorePressed,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final textStyle = AppTypography.standard.copyWith(
      color: theme.textPrimary,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      height: 1.4,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasFiniteWidth = constraints.maxWidth.isFinite;
        final textFit = hasFiniteWidth ? FlexFit.tight : FlexFit.loose;

        final trailing = <Widget>[];
        if (pinned) {
          trailing.addAll([
            const SizedBox(width: Spacing.xs),
            Icon(
              Platform.isIOS ? CupertinoIcons.pin_fill : Icons.push_pin_rounded,
              color: theme.iconSecondary,
              size: IconSize.xs,
            ),
          ]);
        }

        if (isLoading) {
          trailing.addAll([
            const SizedBox(width: Spacing.sm),
            SizedBox(
              width: IconSize.sm,
              height: IconSize.sm,
              child: CircularProgressIndicator(
                strokeWidth: BorderWidth.medium,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.loadingIndicator,
                ),
              ),
            ),
          ]);
        } else if (onMorePressed != null) {
          trailing.addAll([
            const SizedBox(width: Spacing.sm),
            IconButton(
              iconSize: IconSize.sm,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: TouchTarget.listItem,
                minHeight: TouchTarget.listItem,
              ),
              icon: Icon(
                Platform.isIOS
                    ? CupertinoIcons.ellipsis
                    : Icons.more_vert_rounded,
                color: theme.iconSecondary,
              ),
              onPressed: onMorePressed,
              tooltip: AppLocalizations.of(context)!.more,
            ),
          ]);
        }

        return Row(
          mainAxisSize: hasFiniteWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (leading != null) ...[
              SizedBox(
                width: TouchTarget.listItem,
                height: TouchTarget.listItem,
                child: Center(child: leading!),
              ),
              const SizedBox(width: Spacing.sm),
            ],
            Flexible(
              fit: textFit,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
            ...trailing,
          ],
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String title;
  final bool pinned;
  final bool selected;
  final bool isLoading;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMorePressed;

  const _ConversationTile({
    required this.title,
    required this.pinned,
    required this.selected,
    required this.isLoading,
    this.leading,
    required this.onTap,
    this.onLongPress,
    this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final brightness = Theme.of(context).brightness;
    final borderRadius = BorderRadius.zero;
    final Color background = selected
        ? theme.buttonPrimary.withValues(
            alpha: brightness == Brightness.dark ? 0.28 : 0.16,
          )
        : theme.surfaceContainer;
    final Color borderColor = selected
        ? theme.buttonPrimary.withValues(alpha: 0.7)
        : theme.surfaceContainerHighest.withValues(alpha: 0.40);
    final List<BoxShadow> shadow = selected
        ? ConduitShadows.low(context)
        : const [];

    Color? overlayForStates(Set<WidgetState> states) {
      if (states.contains(WidgetState.pressed)) {
        return theme.buttonPrimary.withValues(alpha: Alpha.buttonPressed);
      }
      if (states.contains(WidgetState.focused) ||
          states.contains(WidgetState.hovered)) {
        return theme.buttonPrimary.withValues(alpha: Alpha.hover);
      }
      return Colors.transparent;
    }

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        child: InkWell(
          borderRadius: borderRadius,
          onTap: isLoading ? null : onTap,
          onLongPress: onLongPress,
          overlayColor: WidgetStateProperty.resolveWith(overlayForStates),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: background,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor, width: BorderWidth.thin),
              boxShadow: shadow,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TouchTarget.listItem,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: _ConversationTileContent(
                  title: title,
                  pinned: pinned,
                  selected: selected,
                  isLoading: isLoading,
                  onMorePressed: onMorePressed,
                  leading: leading,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Bottom quick actions widget removed as design now shows only profile card
