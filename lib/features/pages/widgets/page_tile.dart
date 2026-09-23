import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/pages/page_edit_session.dart';
import '../../../core/pages/thumbnail_cache.dart';
import '../../../core/theme/app_theme.dart';

/// One page in the grid: its thumbnail, its number, and whether it is selected.
class PageTile extends StatefulWidget {
  const PageTile({
    super.key,
    required this.page,
    required this.position,
    required this.selected,
    required this.cache,
    required this.onTap,
    this.onLongPress,
  });

  final PageRef page;

  /// One-based position in the edited document, which is what the user counts.
  final int position;
  final bool selected;
  final ThumbnailCache cache;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<PageTile> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.sourceIndex != widget.page.sourceIndex) _load();
  }

  Future<void> _load() async {
    // A page already rendered paints immediately, so scrolling back over the
    // grid never flashes a placeholder.
    final cached = widget.cache.peek(widget.page.sourceIndex);
    if (cached != null) {
      setState(() {
        _bytes = cached;
        _failed = false;
      });
      return;
    }
    setState(() {
      _bytes = null;
      _failed = false;
    });
    try {
      final bytes = await widget.cache.get(widget.page.sourceIndex);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      // A page we cannot render still has to be selectable and movable, so the
      // tile degrades to a placeholder rather than taking the screen down.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;

    return Semantics(
      selected: selected,
      button: true,
      label: 'Page ${widget.position}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(Corners.chip),
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Thumbnail(
                      bytes: _bytes,
                      failed: _failed,
                      quarterTurns: widget.page.rotation ~/ 90,
                    ),
                    if (selected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Icon(
                          Icons.check_circle,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              '${widget.position}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.bytes,
    required this.failed,
    required this.quarterTurns,
  });

  final Uint8List? bytes;
  final bool failed;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (failed) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.outline,
        ),
      );
    }
    final data = bytes;
    if (data == null) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // Rotation is previewed here rather than re-rendered: a quarter turn of an
    // existing bitmap is free, and the engine applies the real rotation on save.
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Image.memory(
        data,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        // A page whose render will not decode must not take the screen down
        // with it: the tile is still selectable and still movable.
        errorBuilder: (context, error, stack) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
