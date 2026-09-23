import 'dart:async';

import 'package:flutter/material.dart';

/// A grid whose items can be dragged into a new order.
///
/// Flutter ships `ReorderableListView` but no grid equivalent, and the page
/// grid is the core of requirements.md 3.6 -- including "drag to reorder, with
/// auto-scroll at the edges". Small enough to own rather than take a
/// dependency for.
class ReorderableGridView extends StatefulWidget {
  const ReorderableGridView({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    this.padding = EdgeInsets.zero,
    this.spacing = 12,
    this.childAspectRatio = 0.72,
    this.enabled = true,
  });

  final int columns;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Called with `ReorderableListView` index semantics: [newIndex] is measured
  /// before the dragged item is removed.
  final void Function(int oldIndex, int newIndex) onReorder;

  final EdgeInsets padding;
  final double spacing;
  final double childAspectRatio;
  final bool enabled;

  @override
  State<ReorderableGridView> createState() => _ReorderableGridViewState();
}

class _ReorderableGridViewState extends State<ReorderableGridView> {
  final _scrollController = ScrollController();
  Timer? _autoScroll;
  int? _dragging;
  int? _hovering;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolls while a drag is held near the top or bottom edge, so a page can be
  /// moved beyond the pages currently on screen.
  void _updateAutoScroll(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    const hotZone = 80.0;
    final height = box.size.height;

    double? velocity;
    if (local.dy < hotZone) {
      velocity = -((hotZone - local.dy) / hotZone) * 18;
    } else if (local.dy > height - hotZone) {
      velocity = ((local.dy - (height - hotZone)) / hotZone) * 18;
    }

    if (velocity == null) {
      _stopAutoScroll();
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) return;
      final target = (_scrollController.offset + _lastVelocity).clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    });
    _lastVelocity = velocity;
  }

  double _lastVelocity = 0;

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _lastVelocity = 0;
  }

  void _drop(int from, int targetIndex) {
    _stopAutoScroll();
    setState(() {
      _dragging = null;
      _hovering = null;
    });
    if (from == targetIndex) return;
    // Convert "insert at targetIndex" into ReorderableListView's convention.
    widget.onReorder(from, from < targetIndex ? targetIndex + 1 : targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: _scrollController,
      padding: widget.padding,
      itemCount: widget.itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columns,
        mainAxisSpacing: widget.spacing,
        crossAxisSpacing: widget.spacing,
        childAspectRatio: widget.childAspectRatio,
      ),
      itemBuilder: (context, index) {
        final child = widget.itemBuilder(context, index);
        if (!widget.enabled) return child;

        return DragTarget<int>(
          onWillAcceptWithDetails: (details) {
            if (details.data == index) return false;
            setState(() => _hovering = index);
            return true;
          },
          onLeave: (_) => setState(() => _hovering = null),
          onAcceptWithDetails: (details) => _drop(details.data, index),
          builder: (context, candidate, rejected) {
            final isTarget = _hovering == index && _dragging != index;
            return AnimatedScale(
              scale: isTarget ? 1.06 : 1,
              duration: const Duration(milliseconds: 120),
              child: LongPressDraggable<int>(
                data: index,
                onDragStarted: () => setState(() => _dragging = index),
                onDragUpdate: (details) =>
                    _updateAutoScroll(details.globalPosition),
                onDraggableCanceled: (_, _) {
                  _stopAutoScroll();
                  setState(() {
                    _dragging = null;
                    _hovering = null;
                  });
                },
                onDragEnd: (_) => _stopAutoScroll(),
                feedback: _Feedback(columns: widget.columns, child: child),
                childWhenDragging: Opacity(opacity: 0.25, child: child),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.columns, required this.child});

  final int columns;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width / columns;
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: SizedBox(width: width, height: width / 0.72, child: child),
      ),
    );
  }
}
