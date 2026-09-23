import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/engine/pdf_engine.dart';
import '../../../core/pages/thumbnail_cache.dart';
import '../../../core/theme/app_theme.dart';

/// One page in the viewer: the rendered page, plus any search highlights.
class ViewerPageView extends StatefulWidget {
  const ViewerPageView({
    super.key,
    required this.pageIndex,
    required this.geometry,
    required this.cache,
    required this.hits,
    required this.currentHit,
  });

  final int pageIndex;
  final PageGeometry geometry;
  final ThumbnailCache cache;

  /// Search hits on this page, in PDF points.
  final List<TextHit> hits;

  /// The hit that is currently selected, if it is on this page.
  final TextHit? currentHit;

  @override
  State<ViewerPageView> createState() => _ViewerPageViewState();
}

class _ViewerPageViewState extends State<ViewerPageView> {
  final _zoom = TransformationController();
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cached = widget.cache.peek(widget.pageIndex);
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    try {
      final bytes = await widget.cache.get(widget.pageIndex);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toggleZoom(TapDownDetails details) {
    final zoomedIn = _zoom.value.getMaxScaleOnAxis() > 1.05;
    if (zoomedIn) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final point = details.localPosition;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-point.dx * (scale - 1), -point.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = widget.geometry.height == 0
        ? 1.0
        : widget.geometry.width / widget.geometry.height;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: AspectRatio(
        aspectRatio: ratio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: GestureDetector(
            onDoubleTapDown: _toggleZoom,
            onDoubleTap: () {},
            child: InteractiveViewer(
              transformationController: _zoom,
              maxScale: 6,
              child: _content(theme, ratio),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, double ratio) {
    if (_failed) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.outline,
        ),
      );
    }
    final data = _bytes;
    if (data == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          data,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
        if (widget.hits.isNotEmpty)
          CustomPaint(
            painter: _HighlightPainter(
              hits: widget.hits,
              current: widget.currentHit,
              geometry: widget.geometry,
              colour: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }
}

/// Draws search hits over the page.
///
/// PDF coordinates start at the bottom-left and the canvas starts at the
/// top-left, so the y axis is flipped here rather than anywhere else.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.hits,
    required this.current,
    required this.geometry,
    required this.colour,
  });

  final List<TextHit> hits;
  final TextHit? current;
  final PageGeometry geometry;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.width == 0 || geometry.height == 0) return;
    final scaleX = size.width / geometry.width;
    final scaleY = size.height / geometry.height;

    for (final hit in hits) {
      final isCurrent = identical(hit, current);
      final rect = Rect.fromLTWH(
        hit.x * scaleX,
        size.height - (hit.y + hit.height) * scaleY,
        hit.width * scaleX,
        hit.height * scaleY,
      ).inflate(1);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = colour.withValues(alpha: isCurrent ? 0.45 : 0.22),
      );
      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colour,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) =>
      oldDelegate.hits != hits || oldDelegate.current != current;
}
