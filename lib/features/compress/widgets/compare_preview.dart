import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/engine/pdf_engine.dart';
import '../../../core/theme/app_theme.dart';

/// Before and after, side by side (requirements.md 3.7).
///
/// The point is that the user can judge the quality loss themselves rather
/// than trusting a percentage, so both panes are pinch-zoomable.
class ComparePreview extends StatefulWidget {
  const ComparePreview({
    super.key,
    required this.engine,
    required this.original,
    required this.compressed,
  });

  final PdfEngine engine;
  final File original;
  final File compressed;

  @override
  State<ComparePreview> createState() => _ComparePreviewState();
}

class _ComparePreviewState extends State<ComparePreview> {
  Uint8List? _before;
  Uint8List? _after;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Rendered large enough that a difference is actually visible.
      final before = await widget.engine
          .renderPage(input: widget.original, pageIndex: 0, maxSize: 700);
      final after = await widget.engine
          .renderPage(input: widget.compressed, pageIndex: 0, maxSize: 700);
      if (mounted) {
        setState(() {
          _before = before;
          _after = after;
        });
      }
    } catch (_) {
      // The numbers still stand without the preview.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_failed) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compare page 1',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Insets.sm),
        SizedBox(
          height: 260,
          child: Row(
            children: [
              Expanded(child: _Pane(label: 'Original', bytes: _before)),
              const SizedBox(width: Insets.md),
              Expanded(child: _Pane(label: 'Compressed', bytes: _after)),
            ],
          ),
        ),
        const SizedBox(height: Insets.xs),
        Text(
          'Pinch to zoom in on either page.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.bytes});

  final String label;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Corners.chip),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: data == null
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : InteractiveViewer(
                    maxScale: 5,
                    child: Image.memory(
                      data,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) =>
                          const SizedBox.shrink(),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
