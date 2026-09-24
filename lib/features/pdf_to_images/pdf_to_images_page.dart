import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/engine/pdf_failure.dart';
import '../../core/entitlements/tool_limits.dart';
import '../../core/files/file_importer.dart';
import '../../core/images/gallery_saver.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/page_ranges.dart';
import '../shared/job_views.dart';
import 'pdf_to_images_operation.dart';

/// PDF to images (requirements.md 3.9).
class PdfToImagesPage extends StatefulWidget {
  const PdfToImagesPage({super.key});

  @override
  State<PdfToImagesPage> createState() => _PdfToImagesPageState();
}

class _PdfToImagesPageState extends State<PdfToImagesPage> {
  final _job = JobController<List<File>>();
  final _rangeController = TextEditingController();

  ImportedDocument? _document;
  int? _pageCount;
  bool _allPages = true;
  ExportDpi _dpi = ExportDpi.good;
  ImageFormat _format = ImageFormat.jpg;
  ExportEstimate? _estimate;
  PdfFailure? _failure;
  bool _estimating = false;

  @override
  void initState() {
    super.initState();
    _job.addListener(_onJobChanged);
  }

  @override
  void dispose() {
    _rangeController.dispose();
    _job
      ..removeListener(_onJobChanged)
      ..dispose();
    super.dispose();
  }

  void _onJobChanged() {
    if (!mounted) return;
    setState(() {});
    final files = _job.result;
    if (_job.status == JobStatus.success && files != null) {
      AppServicesScope.of(context).export.share(files);
    }
  }

  /// The pages the current settings would export, or null if the input is not
  /// valid yet.
  List<int>? get _pageIndices {
    final pages = _pageCount;
    if (pages == null) return null;
    if (_allPages) return [for (var i = 0; i < pages; i++) i];
    return switch (parsePageRanges(_rangeController.text, pageCount: pages)) {
      PageRangesParsed(:final ranges) => [
          for (final range in ranges) ...range.indices,
        ],
      PageRangesInvalid() => null,
    };
  }

  String? get _rangeError {
    if (_allPages || _pageCount == null) return null;
    if (_rangeController.text.trim().isEmpty) return null;
    return switch (
        parsePageRanges(_rangeController.text, pageCount: _pageCount!)) {
      PageRangesInvalid(:final message) => message,
      PageRangesParsed() => null,
    };
  }

  Future<void> _choose() async {
    setState(() => _failure = null);
    final services = AppServicesScope.of(context);
    try {
      final picked = await services.importer.pickPdfs(multiple: false);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _document = picked.first;
        _pageCount = null;
        _estimate = null;
      });
      final info = await services.engine.inspect(picked.first.file);
      if (!mounted) return;
      setState(() => _pageCount = info.pageCount);
      await _refreshEstimate();
    } on PdfFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  /// Renders one page for real, so the quoted total is close to the truth
  /// rather than a guess (requirements.md 3.9).
  Future<void> _refreshEstimate() async {
    final indices = _pageIndices;
    final document = _document;
    if (indices == null || indices.isEmpty || document == null) {
      setState(() => _estimate = null);
      return;
    }
    setState(() => _estimating = true);
    try {
      final estimate = await estimateExport(
        services: AppServicesScope.of(context),
        source: document.file,
        pageIndices: indices,
        dpi: _dpi,
        format: _format,
      );
      if (mounted) {
        setState(() {
          _estimate = estimate;
          _estimating = false;
        });
      }
    } on PdfFailure {
      if (mounted) {
        setState(() {
          _estimate = null;
          _estimating = false;
        });
      }
    }
  }

  Future<void> _run() async {
    final indices = _pageIndices!;
    if (indices.length > kManyImagesThreshold) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Export ${indices.length} images?'),
          content: Text(
            'That is a lot of files to handle at once. You can export a '
            'smaller range instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Export anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final services = AppServicesScope.of(context);
    final source = _document!.file;
    final dpi = _dpi;
    final format = _format;
    _job.run((handle) => exportPagesAsImages(
          services: services,
          source: source,
          pageIndices: indices,
          dpi: dpi,
          format: format,
          handle: handle,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = _job.isRunning;
    final indices = _pageIndices;
    final exported = _job.result;

    return Scaffold(
      appBar: AppBar(title: const Text('PDF to images')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Insets.lg),
          children: [
            if (_failure case final failure?) ...[
              FailureView(failure: failure),
              const SizedBox(height: Insets.lg),
            ],
            if (_job.failure case final failure?) ...[
              FailureView(failure: failure, onRetry: _run),
              const SizedBox(height: Insets.lg),
            ],
            if (_document == null)
              _ChooseCard(onChoose: _choose)
            else ...[
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    _document!.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _pageCount == null ? 'Reading...' : '$_pageCount pages',
                  ),
                  trailing: TextButton(
                    onPressed: running ? null : _choose,
                    child: const Text('Change'),
                  ),
                ),
              ),
              const SizedBox(height: Insets.lg),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('All pages')),
                  ButtonSegment(value: false, label: Text('Some pages')),
                ],
                selected: {_allPages},
                onSelectionChanged: running
                    ? null
                    : (selection) {
                        setState(() => _allPages = selection.first);
                        _refreshEstimate();
                      },
              ),
              if (!_allPages) ...[
                const SizedBox(height: Insets.md),
                TextField(
                  controller: _rangeController,
                  enabled: !running,
                  onChanged: (_) {
                    setState(() {});
                    _refreshEstimate();
                  },
                  decoration: InputDecoration(
                    labelText: 'Pages',
                    hintText: '1-5, 8, 11-13',
                    errorText: _rangeError,
                  ),
                ),
              ],
              const SizedBox(height: Insets.lg),
              _Chips<ImageFormat>(
                label: 'Format',
                values: ImageFormat.values,
                selected: _format,
                labelOf: (v) => v.label,
                enabled: !running,
                onChanged: (v) {
                  setState(() => _format = v);
                  _refreshEstimate();
                },
              ),
              _Chips<ExportDpi>(
                label: 'Resolution',
                values: ExportDpi.values,
                selected: _dpi,
                labelOf: (v) => '${v.label} (${v.dpi} dpi)',
                enabled: !running,
                // Requirements.md 9: 300 dpi is premium, and the card says so.
                isLocked: (v) =>
                    !AppServicesScope.of(context).entitlements.isPremium &&
                    v.dpi > ToolLimits.maxFreeDpi,
                onChanged: (v) {
                  setState(() => _dpi = v);
                  _refreshEstimate();
                },
                onLockedTap: () => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                    content: Text(
                      'The free version exports up to 150 dpi.',
                    ),
                  )),
              ),
              const SizedBox(height: Insets.sm),
              _EstimateCard(
                estimate: _estimate,
                estimating: _estimating,
                format: _format,
              ),
              const SizedBox(height: Insets.lg),
              if (running)
                JobProgressView(
                  progress: _job.progress,
                  onCancel: _job.cancel,
                )
              else if (exported != null)
                _Exported(files: exported, onAgain: () => _job.reset())
              else
                FilledButton(
                  onPressed: indices == null || indices.isEmpty ? null : _run,
                  child: Text(
                    indices == null || indices.isEmpty
                        ? 'Choose pages to export'
                        : 'Export ${indices.length} image'
                            '${indices.length == 1 ? '' : 's'}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.estimate,
    required this.estimating,
    required this.format,
  });

  final ExportEstimate? estimate;
  final bool estimating;
  final ImageFormat format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Row(
          children: [
            Icon(Icons.straighten, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Insets.md),
            Expanded(
              child: estimating || estimate == null
                  ? Text(
                      estimating ? 'Measuring one page...' : format.hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${estimate!.pageCount} '
                          '${format.label} file'
                          '${estimate!.pageCount == 1 ? '' : 's'} · '
                          '${estimate!.pixelWidth} × '
                          '${estimate!.pixelHeight} px',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'About ${formatBytes(estimate!.totalBytes)} in total, '
                          'measured from one page.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
}

class _Exported extends StatefulWidget {
  const _Exported({required this.files, required this.onAgain});

  final List<File> files;
  final VoidCallback onAgain;

  @override
  State<_Exported> createState() => _ExportedState();
}

class _ExportedState extends State<_Exported> {
  bool _saving = false;

  Future<void> _saveToPhotos() async {
    final services = AppServicesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final outcome = await services.gallery.save(widget.files, album: 'PDF Toolbox');
    if (!mounted) return;
    setState(() => _saving = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(switch (outcome) {
          GallerySaveOutcome.saved =>
            'Saved ${widget.files.length} to your photos.',
          GallerySaveOutcome.denied =>
            'Photo access is off. You can turn it on in Settings.',
          GallerySaveOutcome.failed => "Couldn't save to your photos.",
        }),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = widget.files;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    '${files.length} image'
                    '${files.length == 1 ? '' : 's'} exported and shared.',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.md),
        if (AppServicesScope.of(context).gallery.isSupported)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _saveToPhotos,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_saving ? 'Saving...' : 'Save to Photos'),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onAgain,
                child: const Text('Export again'),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    AppServicesScope.of(context).export.share(files),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.enabled,
    required this.onChanged,
    this.isLocked,
    this.onLockedTap,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final bool enabled;
  final ValueChanged<T> onChanged;

  /// Options the free tier cannot pick. Shown, but with a lock, so the limit
  /// is visible rather than the option quietly missing.
  final bool Function(T)? isLocked;
  final VoidCallback? onLockedTap;

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
                  avatar: (isLocked?.call(value) ?? false)
                      ? const Icon(Icons.lock_outline, size: 16)
                      : null,
                  selected: value == selected,
                  onSelected: !enabled
                      ? null
                      : (_) => (isLocked?.call(value) ?? false)
                          ? onLockedTap?.call()
                          : onChanged(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChooseCard extends StatelessWidget {
  const _ChooseCard({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
      child: Column(
        children: [
          Icon(Icons.collections_outlined,
              size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: Insets.lg),
          Text('Save pages as pictures', style: theme.textTheme.titleMedium),
          const SizedBox(height: Insets.xs),
          Text(
            'Export every page, or just the ones you need.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Insets.xl),
          FilledButton.icon(
            onPressed: onChoose,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose a PDF'),
          ),
        ],
      ),
    );
  }
}
