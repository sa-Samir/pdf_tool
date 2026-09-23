import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/engine/pdf_failure.dart';
import '../../core/images/image_normalizer.dart';
import '../../core/images/page_layout.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../shared/job_views.dart';
import '../shared/result_page.dart';
import 'images_to_pdf_operation.dart';

/// Images to PDF (requirements.md 3.8).
class ImagesToPdfPage extends StatefulWidget {
  const ImagesToPdfPage({super.key});

  @override
  State<ImagesToPdfPage> createState() => _ImagesToPdfPageState();
}

class _ImagesToPdfPageState extends State<ImagesToPdfPage> {
  final _job = JobController<File>();
  final _images = <PickedImage>[];
  ImagePageOptions _options = const ImagePageOptions();
  PdfFailure? _importFailure;

  @override
  void initState() {
    super.initState();
    _job.addListener(_onJobChanged);
  }

  @override
  void dispose() {
    _job
      ..removeListener(_onJobChanged)
      ..dispose();
    super.dispose();
  }

  void _onJobChanged() {
    if (!mounted) return;
    setState(() {});
    final output = _job.result;
    if (_job.status == JobStatus.success && output != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultPage(
            title: 'Images to PDF',
            files: [output],
            summary: '${_images.length} image'
                '${_images.length == 1 ? '' : 's'} → '
                '${_images.length} page'
                '${_images.length == 1 ? '' : 's'}',
          ),
        ),
      );
    }
  }

  Future<void> _add() async {
    setState(() => _importFailure = null);
    final services = AppServicesScope.of(context);
    try {
      final picked = await services.importer.pickImages();
      if (!mounted || picked.isEmpty) return;
      setState(() => _images.addAll(
            [for (final doc in picked) PickedImage(document: doc)],
          ));
    } on PdfFailure catch (failure) {
      if (mounted) setState(() => _importFailure = failure);
    }
  }

  void _run() {
    final services = AppServicesScope.of(context);
    final images = List.of(_images);
    final options = _options;
    _job.run((handle) => imagesToPdfDocument(
          services: services,
          images: images,
          options: options,
          handle: handle,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final running = _job.isRunning;

    return Scaffold(
      appBar: AppBar(title: const Text('Images to PDF')),
      body: SafeArea(
        child: Column(
          children: [
            if (_importFailure case final failure?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Insets.lg, Insets.lg, Insets.lg, 0),
                child: FailureView(failure: failure),
              ),
            if (_job.failure case final failure?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Insets.lg, Insets.lg, Insets.lg, 0),
                child: FailureView(failure: failure, onRetry: _run),
              ),
            if (running)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Insets.lg, Insets.lg, Insets.lg, 0),
                child: JobProgressView(
                  progress: _job.progress,
                  onCancel: _job.cancel,
                ),
              ),
            Expanded(
              child: _images.isEmpty
                  ? _EmptyState(onChoose: _add)
                  : _body(running),
            ),
            if (_images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(Insets.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: running ? null : _add,
                        icon: const Icon(Icons.add),
                        label: const Text('Add more'),
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: running ? null : _run,
                        child: Text(
                          'Create ${_images.length} page'
                          '${_images.length == 1 ? '' : 's'}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(bool running) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _images.length,
          onReorder: (oldIndex, newIndex) => setState(() {
            if (newIndex > oldIndex) newIndex--;
            _images.insert(newIndex, _images.removeAt(oldIndex));
          }),
          itemBuilder: (context, index) {
            final image = _images[index];
            return Padding(
              key: ValueKey('${image.document.file.path}-$index'),
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: Card(
                child: ListTile(
                  leading: Icon(
                    Icons.image_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    image.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    image.quarterTurns == 0
                        ? formatBytes(image.document.sizeBytes)
                        : '${formatBytes(image.document.sizeBytes)} · '
                            'rotated ${image.quarterTurns * 90}°',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                        tooltip: 'Rotate ${image.name}',
                        onPressed: running
                            ? null
                            : () => setState(
                                () => _images[index] = image.rotated(1)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove ${image.name}',
                        onPressed: running
                            ? null
                            : () => setState(() => _images.removeAt(index)),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        enabled: !running,
                        child: const Padding(
                          padding: EdgeInsets.all(Insets.sm),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: Insets.lg),
        Text('Page setup',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: Insets.md),
        _Choice<PageSize>(
          label: 'Size',
          values: PageSize.values,
          selected: _options.size,
          labelOf: (v) => v.label,
          enabled: !running,
          onChanged: (v) => setState(() => _options = _options.copyWith(size: v)),
        ),
        _Choice<PageOrientation>(
          label: 'Orientation',
          values: PageOrientation.values,
          selected: _options.orientation,
          labelOf: (v) => v.label,
          enabled: !running && !_options.size.followsImage,
          onChanged: (v) =>
              setState(() => _options = _options.copyWith(orientation: v)),
        ),
        _Choice<PageMargin>(
          label: 'Margin',
          values: PageMargin.values,
          selected: _options.margin,
          labelOf: (v) => v.label,
          enabled: !running,
          onChanged: (v) =>
              setState(() => _options = _options.copyWith(margin: v)),
        ),
        _Choice<ImageFit>(
          label: 'Fit',
          values: ImageFit.values,
          selected: _options.fit,
          labelOf: (v) => v.label,
          enabled: !running,
          onChanged: (v) => setState(() => _options = _options.copyWith(fit: v)),
        ),
        _Choice<ImageQuality>(
          label: 'Quality',
          values: ImageQuality.values,
          selected: _options.quality,
          labelOf: (v) => v.label,
          enabled: !running,
          onChanged: (v) =>
              setState(() => _options = _options.copyWith(quality: v)),
        ),
        const SizedBox(height: Insets.sm),
        Text(
          _options.fit == ImageFit.fill
              ? 'Fill crops the edges that do not fit the page.'
              : 'Fit keeps the whole image, leaving space at the edges.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Insets.xs),
          Wrap(
            spacing: Insets.sm,
            children: [
              for (final value in values)
                ChoiceChip(
                  label: Text(labelOf(value)),
                  selected: value == selected,
                  onSelected: enabled ? (_) => onChanged(value) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: Insets.lg),
            Text('Turn photos into a PDF',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: Insets.xs),
            Text(
              'One image per page. You can reorder and rotate them first.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.xl),
            FilledButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose images'),
            ),
          ],
        ),
      ),
    );
  }
}
