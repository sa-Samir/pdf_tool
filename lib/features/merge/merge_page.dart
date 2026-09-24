import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/engine/pdf_failure.dart';
import '../../core/entitlements/tool_limits.dart';
import '../../core/files/file_importer.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../shared/job_views.dart';
import '../shared/result_page.dart';
import 'merge_operation.dart';

/// Merge (requirements.md 3.4).
class MergePage extends StatefulWidget {
  const MergePage({super.key});

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  final _job = JobController<File>();
  final _documents = <ImportedDocument>[];
  final _pageCounts = <String, int?>{};
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
            title: 'Merged',
            files: [output],
            summary: '${_documents.length} files merged'
                '${_totalPages == null ? '' : ' into $_totalPages pages'}',
          ),
        ),
      );
    }
  }

  int? get _totalPages {
    var sum = 0;
    for (final doc in _documents) {
      final count = _pageCounts[doc.file.path];
      if (count == null) return null;
      sum += count;
    }
    return sum;
  }

  Future<void> _addFiles() async {
    setState(() => _importFailure = null);
    final services = AppServicesScope.of(context);
    try {
      final picked = await services.importer.pickPdfs();
      if (!mounted || picked.isEmpty) return;

      // Requirements.md 9: the free tier merges up to three files, and the
      // card says so, so the limit has to be real.
      final isPremium = services.entitlements.isPremium;
      final room = isPremium
          ? picked.length
          : (ToolLimits.mergeFreeFiles - _documents.length)
              .clamp(0, picked.length);
      if (room < picked.length) {
        _reportCapped(
          'The free version merges up to ${ToolLimits.mergeFreeFiles} '
          'files at a time.',
        );
      }
      if (room == 0) return;
      final accepted = picked.take(room).toList();
      setState(() => _documents.addAll(accepted));
      for (final doc in accepted) {
        _loadPageCount(doc);
      }
    } on PdfFailure catch (failure) {
      if (mounted) setState(() => _importFailure = failure);
    }
  }

  void _reportCapped(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadPageCount(ImportedDocument doc) async {
    final services = AppServicesScope.of(context);
    try {
      final info = await services.engine.inspect(doc.file);
      if (mounted) setState(() => _pageCounts[doc.file.path] = info.pageCount);
    } on PdfFailure {
      // A file we cannot read is reported when the merge runs, not as a
      // surprise while the list is still being built.
      if (mounted) setState(() => _pageCounts[doc.file.path] = null);
    }
  }

  void _run() {
    final services = AppServicesScope.of(context);
    final inputs = [for (final d in _documents) d.file];
    final expected = _totalPages;

    _job.run((handle) => mergeDocuments(
          services: services,
          inputs: inputs,
          handle: handle,
          expectedPages: expected,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = _job.isRunning;
    final canMerge = _documents.length >= 2 && !running;

    return Scaffold(
      appBar: AppBar(title: const Text('Merge')),
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
              child: _documents.isEmpty
                  ? _EmptyState(onChoose: _addFiles)
                  : _FileList(
                      documents: _documents,
                      pageCounts: _pageCounts,
                      enabled: !running,
                      onReorder: (oldIndex, newIndex) => setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        _documents.insert(
                            newIndex, _documents.removeAt(oldIndex));
                      }),
                      onRemove: (index) =>
                          setState(() => _documents.removeAt(index)),
                    ),
            ),
            if (_documents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(Insets.lg),
                child: Column(
                  children: [
                    if (_documents.length < 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Insets.sm),
                        child: Text(
                          'Add at least one more PDF to merge.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: running ? null : _addFiles,
                            icon: const Icon(Icons.add),
                            label: const Text('Add more'),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: canMerge ? _run : null,
                            child: Text(
                              'Merge ${_documents.length} '
                              'file${_documents.length == 1 ? '' : 's'}',
                            ),
                          ),
                        ),
                      ],
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
            Icon(Icons.merge_type, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: Insets.lg),
            Text('Combine PDFs into one', style: theme.textTheme.titleMedium),
            const SizedBox(height: Insets.xs),
            Text(
              'Choose two or more PDFs. You can reorder them before merging.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.xl),
            FilledButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choose PDFs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.documents,
    required this.pageCounts,
    required this.enabled,
    required this.onReorder,
    required this.onRemove,
  });

  final List<ImportedDocument> documents;
  final Map<String, int?> pageCounts;
  final bool enabled;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(Insets.lg),
      buildDefaultDragHandles: false,
      itemCount: documents.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final pages = pageCounts[doc.file.path];
        return Padding(
          key: ValueKey(doc.file.path),
          padding: const EdgeInsets.only(bottom: Insets.sm),
          child: Card(
            child: ListTile(
              leading: Icon(
                Icons.picture_as_pdf_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                doc.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                pages == null
                    ? formatBytes(doc.sizeBytes)
                    : '$pages page${pages == 1 ? '' : 's'} · '
                        '${formatBytes(doc.sizeBytes)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove ${doc.displayName}',
                    onPressed: enabled ? () => onRemove(index) : null,
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    enabled: enabled,
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
    );
  }
}
