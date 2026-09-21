import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/engine/pdf_failure.dart';
import '../../core/files/file_importer.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/page_ranges.dart';
import '../shared/job_views.dart';
import '../shared/result_page.dart';
import 'split_operation.dart';

enum SplitMode { everyPage, ranges, everyN }

/// Split (requirements.md 3.5).
class SplitPage extends StatefulWidget {
  const SplitPage({super.key});

  @override
  State<SplitPage> createState() => _SplitPageState();
}

class _SplitPageState extends State<SplitPage> {
  final _job = JobController<List<File>>();
  final _rangeController = TextEditingController();

  ImportedDocument? _document;
  int? _pageCount;
  SplitMode _mode = SplitMode.everyPage;
  int _everyN = 2;
  PdfFailure? _failure;

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
    final outputs = _job.result;
    if (_job.status == JobStatus.success && outputs != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultPage(
            title: 'Split',
            files: outputs,
            summary: '${outputs.length} file${outputs.length == 1 ? '' : 's'} '
                'from $_pageCount pages',
          ),
        ),
      );
    }
  }

  /// The ranges the current settings would produce, or null when the input is
  /// not valid yet. One source of truth for the preview, the button's enabled
  /// state and the run itself.
  List<PageRange>? get _plannedRanges {
    final pages = _pageCount;
    if (pages == null || pages < 1) return null;
    return switch (_mode) {
      SplitMode.everyPage => [for (var i = 1; i <= pages; i++) PageRange(i, i)],
      SplitMode.everyN => [
          for (var start = 1; start <= pages; start += _everyN)
            PageRange(start, (start + _everyN - 1).clamp(1, pages)),
        ],
      SplitMode.ranges => switch (
            parsePageRanges(_rangeController.text, pageCount: pages)) {
          PageRangesParsed(:final ranges) => ranges,
          PageRangesInvalid() => null,
        },
    };
  }

  String? get _rangeError {
    if (_mode != SplitMode.ranges) return null;
    final pages = _pageCount;
    if (pages == null) return null;
    if (_rangeController.text.trim().isEmpty) return null;
    return switch (parsePageRanges(_rangeController.text, pageCount: pages)) {
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
      final doc = picked.first;
      setState(() {
        _document = doc;
        _pageCount = null;
      });
      final info = await services.engine.inspect(doc.file);
      if (mounted) setState(() => _pageCount = info.pageCount);
    } on PdfFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  void _run() {
    final services = AppServicesScope.of(context);
    final source = _document!.file;
    final ranges = _plannedRanges!;

    _job.run((handle) => splitDocument(
          services: services,
          source: source,
          ranges: ranges,
          handle: handle,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = _job.isRunning;
    final planned = _plannedRanges;

    return Scaffold(
      appBar: AppBar(title: const Text('Split')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Insets.lg),
          children: [
            if (_failure case final failure?)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.lg),
                child: FailureView(failure: failure),
              ),
            if (_job.failure case final failure?)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.lg),
                child: FailureView(failure: failure, onRetry: _run),
              ),
            if (running)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.lg),
                child: JobProgressView(
                  progress: _job.progress,
                  onCancel: _job.cancel,
                ),
              ),
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
                    _pageCount == null
                        ? 'Reading...'
                        : '$_pageCount pages · '
                            '${formatBytes(_document!.sizeBytes)}',
                  ),
                  trailing: TextButton(
                    onPressed: running ? null : _choose,
                    child: const Text('Change'),
                  ),
                ),
              ),
              const SizedBox(height: Insets.xl),
              Text('How should it be split?',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: Insets.md),
              SegmentedButton<SplitMode>(
                segments: const [
                  ButtonSegment(
                      value: SplitMode.everyPage, label: Text('Every page')),
                  ButtonSegment(value: SplitMode.ranges, label: Text('Ranges')),
                  ButtonSegment(
                      value: SplitMode.everyN, label: Text('Every N')),
                ],
                selected: {_mode},
                onSelectionChanged: running
                    ? null
                    : (selection) => setState(() => _mode = selection.first),
              ),
              const SizedBox(height: Insets.lg),
              if (_mode == SplitMode.ranges)
                TextField(
                  controller: _rangeController,
                  enabled: !running,
                  keyboardType: TextInputType.text,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Pages',
                    hintText: '1-5, 8, 11-13',
                    errorText: _rangeError,
                    helperText: _rangeError == null
                        ? 'Separate ranges with commas.'
                        : null,
                  ),
                ),
              if (_mode == SplitMode.everyN)
                Row(
                  children: [
                    Expanded(
                      child: Text('Pages per file: $_everyN',
                          style: theme.textTheme.bodyMedium),
                    ),
                    IconButton.outlined(
                      onPressed: running || _everyN <= 1
                          ? null
                          : () => setState(() => _everyN--),
                      icon: const Icon(Icons.remove),
                      tooltip: 'Fewer pages per file',
                    ),
                    const SizedBox(width: Insets.sm),
                    IconButton.outlined(
                      onPressed: running || _everyN >= (_pageCount ?? 1)
                          ? null
                          : () => setState(() => _everyN++),
                      icon: const Icon(Icons.add),
                      tooltip: 'More pages per file',
                    ),
                  ],
                ),
              const SizedBox(height: Insets.lg),
              // Requirements.md 3.5: say what will be produced before committing.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Insets.lg),
                  child: Text(
                    planned == null
                        ? 'Nothing to split yet.'
                        : 'Creates ${planned.length} file'
                            '${planned.length == 1 ? '' : 's'}: '
                            '${_previewNames(planned)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Insets.lg),
              FilledButton(
                onPressed: planned == null || planned.isEmpty || running
                    ? null
                    : _run,
                child: const Text('Split'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _previewNames(List<PageRange> ranges) {
    final stem = p.basenameWithoutExtension(_document!.file.path);
    final shown = ranges.take(3).map((r) => '${stem}_$r.pdf').join(', ');
    return ranges.length <= 3 ? shown : '$shown, ...';
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
          Icon(Icons.call_split, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: Insets.lg),
          Text('Break a PDF apart', style: theme.textTheme.titleMedium),
          const SizedBox(height: Insets.xs),
          Text(
            'Split into single pages, custom ranges, or fixed-size chunks.',
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
