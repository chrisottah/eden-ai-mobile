import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'skeleton_loader.dart';
import 'package:eden_ai/l10n/app_localizations.dart';
import 'improved_loading_states.dart';

/// Optimized list widget with virtualization and performance enhancements
class OptimizedList<T> extends ConsumerStatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? separatorBuilder;
  final Widget? loadingWidget;
  final Widget? emptyWidget;
  final String? emptyMessage;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoading;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final Axis scrollDirection;
  final bool reverse;
  final double? cacheExtent;
  final int? itemExtent;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool enablePagination;
  final double paginationThreshold;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  const OptimizedList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.separatorBuilder,
    this.loadingWidget,
    this.emptyWidget,
    this.emptyMessage,
    this.onRefresh,
    this.onLoadMore,
    this.hasMore = false,
    this.isLoading = false,
    this.padding,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.cacheExtent,
    this.itemExtent,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.enablePagination = false,
    this.paginationThreshold = 0.8,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
  });

  @override
  ConsumerState<OptimizedList<T>> createState() => _OptimizedListState<T>();
}

class _OptimizedListState<T> extends ConsumerState<OptimizedList<T>> {
  late ScrollController _scrollController;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();

    if (widget.enablePagination) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (!widget.enablePagination ||
        _isLoadingMore ||
        !widget.hasMore ||
        widget.onLoadMore == null) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * widget.paginationThreshold;

    if (currentScroll >= threshold) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      widget.onLoadMore?.call();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading state
    if (widget.isLoading && widget.items.isEmpty) {
      return widget.loadingWidget ?? _buildDefaultLoadingWidget();
    }

    // Show empty state
    if (widget.items.isEmpty) {
      return widget.emptyWidget ??
          ImprovedEmptyState(
            title: AppLocalizations.of(context)!.noItems,
            subtitle:
                widget.emptyMessage ??
                AppLocalizations.of(context)!.noItemsToDisplay,
            icon: Icons.inbox_outlined,
          );
    }

    // Build the list
    Widget listWidget;

    final ScrollPhysics effectivePhysics =
        widget.physics ??
        (widget.onRefresh != null
            ? const AlwaysScrollableScrollPhysics()
            : const ClampingScrollPhysics());

    final reverse = widget.reverse;

    if (widget.separatorBuilder != null) {
      listWidget = ListView.separated(
        controller: _scrollController,
        padding: widget.padding,
        physics: effectivePhysics,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        shrinkWrap: widget.shrinkWrap,
        scrollDirection: widget.scrollDirection,
        reverse: reverse,
        cacheExtent: widget.cacheExtent ?? 250.0,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
        separatorBuilder: (context, index) => widget.separatorBuilder!,
        itemBuilder: (context, index) {
          if (index >= widget.items.length) {
            return _buildLoadMoreIndicator();
          }

          return _buildOptimizedItem(context, index, reverse: reverse);
        },
      );
    } else {
      listWidget = ListView.builder(
        controller: _scrollController,
        padding: widget.padding,
        physics: effectivePhysics,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        shrinkWrap: widget.shrinkWrap,
        scrollDirection: widget.scrollDirection,
        reverse: reverse,
        cacheExtent: widget.cacheExtent ?? 250.0,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
        itemExtent: widget.itemExtent?.toDouble(),
        itemBuilder: (context, index) {
          if (index >= widget.items.length) {
            return _buildLoadMoreIndicator();
          }

          return _buildOptimizedItem(context, index, reverse: reverse);
        },
      );
    }

    // Add refresh indicator if enabled
    if (widget.onRefresh != null) {
      return RefreshIndicator(onRefresh: widget.onRefresh!, child: listWidget);
    }

    return listWidget;
  }

  Widget _buildOptimizedItem(
    BuildContext context,
    int index, {
    required bool reverse,
  }) {
    final effectiveIndex = reverse ? widget.items.length - index - 1 : index;
    final item = widget.items[effectiveIndex];

    if (widget.addRepaintBoundaries) {
      return RepaintBoundary(
        child: widget.itemBuilder(context, item, effectiveIndex),
      );
    }

    return widget.itemBuilder(context, item, effectiveIndex);
  }

  Widget _buildLoadMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? const CircularProgressIndicator()
          : TextButton(
              onPressed: _loadMore,
              child: Text(AppLocalizations.of(context)!.loadMore),
            ),
    );
  }

  Widget _buildDefaultLoadingWidget() {
    return ListView.builder(
      padding: widget.padding,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: 5,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SkeletonLoader(height: 80),
      ),
    );
  }
}

/// Sliver version of OptimizedList for use in CustomScrollView
class OptimizedSliverList<T> extends ConsumerWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? loadingWidget;
  final Widget? emptyWidget;
  final String? emptyMessage;
  final bool isLoading;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;

  const OptimizedSliverList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.loadingWidget,
    this.emptyWidget,
    this.emptyMessage,
    this.isLoading = false,
    this.hasMore = false,
    this.onLoadMore,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show loading state
    if (isLoading && items.isEmpty) {
      return SliverToBoxAdapter(
        child: loadingWidget ?? _buildDefaultLoadingWidget(),
      );
    }

    // Show empty state
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child:
            emptyWidget ??
            Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context)!;
                return ImprovedEmptyState(
                  title: l10n.noItems,
                  subtitle: emptyMessage ?? l10n.noItemsToDisplay,
                  icon: Icons.inbox_outlined,
                );
              },
            ),
      );
    }

    // Build the list
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= items.length) {
            if (hasMore) {
              // Trigger load more
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onLoadMore?.call();
              });

              return Container(
                padding: const EdgeInsets.all(16.0),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            }
            return null;
          }

          final item = items[index];
          final widget = itemBuilder(context, item, index);

          // Wrap in repaint boundary for performance
          if (addRepaintBoundaries) {
            return RepaintBoundary(child: widget);
          }

          return widget;
        },
        childCount: items.length + (hasMore ? 1 : 0),
        addAutomaticKeepAlives: addAutomaticKeepAlives,
        addRepaintBoundaries: addRepaintBoundaries,
      ),
    );
  }

  Widget _buildDefaultLoadingWidget() {
    return Column(
      children: List.generate(
        5,
        (index) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SkeletonLoader(height: 80),
        ),
      ),
    );
  }
}

/// Animated list with optimizations
class OptimizedAnimatedList<T> extends ConsumerStatefulWidget {
  final List<T> items;
  final Widget Function(
    BuildContext context,
    T item,
    int index,
    Animation<double> animation,
  )
  itemBuilder;
  final Duration animationDuration;
  final Curve animationCurve;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;
  final bool shrinkWrap;

  const OptimizedAnimatedList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.padding,
    this.scrollController,
    this.shrinkWrap = false,
  });

  @override
  ConsumerState<OptimizedAnimatedList<T>> createState() =>
      _OptimizedAnimatedListState<T>();
}

class _OptimizedAnimatedListState<T>
    extends ConsumerState<OptimizedAnimatedList<T>> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<T> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  @override
  void didUpdateWidget(OptimizedAnimatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle item additions
    for (int i = 0; i < widget.items.length; i++) {
      if (i >= _items.length || widget.items[i] != _items[i]) {
        _items.insert(i, widget.items[i]);
        _listKey.currentState?.insertItem(
          i,
          duration: widget.animationDuration,
        );
      }
    }

    // Handle item removals
    for (int i = _items.length - 1; i >= widget.items.length; i--) {
      final removedItem = _items[i];
      _items.removeAt(i);
      _listKey.currentState?.removeItem(
        i,
        (context, animation) =>
            widget.itemBuilder(context, removedItem, i, animation),
        duration: widget.animationDuration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      controller: widget.scrollController,
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        if (index >= _items.length) return const SizedBox.shrink();

        return widget.itemBuilder(context, _items[index], index, animation);
      },
    );
  }
}
