import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/engine/pdf_failure.dart';
import '../../core/files/save_target.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/models/pdf_tool.dart';
import '../../core/pages/page_edit_session.dart';
import '../../core/pages/thumbnail_cache.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../shared/job_views.dart';
import '../shared/save_choice_sheet.dart';
import '../shared/result_page.dart';
import 'page_operation.dart';
import 'widgets/page_tile.dart';
import 'widgets/reorderable_grid.dart';

/// The page-management screen (requirements.md 3.6).
///
/// One screen behind Reorder, Rotate, Delete, Duplicate and Extract. The tool
/// the user picked only decides the hint and which action is emphasised -- the
/// edits themselves are all available at once, with a single undo stack and one
/// save, because that is how people actually tidy a document.
class PageGridPage extends StatefulWidget {
  const PageGridPage({super.key, required this.tool, this.source});

  final PdfTool tool;

  /// Opened straight from the library, so the result can replace it. Null
  /// when the user will pick a file instead.
  final EditableSource? source;

  @override
  State<PageGridPage> createState() => _PageGridPageState();
}

class _PageGridPageState extends State<PageGridPage> {
  final _job = JobController<File>();

  EditableSource? _source;
  PageEditSession? _session;
  ThumbnailCache? _cache;
  PdfFailure? _failure;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _job.addListener(_onJobChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.source != null && _source == null) _load(widget.source!);
  }

  @override
  void dispose() {
    _job
      ..removeListener(_onJobChanged)
      ..dispose();
    _session?.dispose();
    _cache?.dispose();
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
            title: widget.tool.label,
            files: [output],
            summary: '${_session!.pageCount} page'
                '${_session!.pageCount == 1 ? '' : 's'} saved',
          ),
        ),
      );
    }
  }

  Future<void> _choose() async {
    setState(() => _failure = null);
    final services = AppServicesScope.of(context);
    try {
      final picked = await services.importer.pickPdfs(multiple: false);
      if (!mounted || picked.isEmpty) return;
      final doc = picked.first;
      await _load(EditableSource.imported(
        file: doc.file,
        displayName: doc.displayName,
      ));
    } on PdfFailure catch (failure) {
      if (mounted) {
        setState(() {
          _failure = failure;
          _loading = false;
          _source = null;
        });
      }
    }
  }

  Future<void> _load(EditableSource source) async {
    final services = AppServicesScope.of(context);
    setState(() {
      _source = source;
      _loading = true;
      _failure = null;
    });
    try {
      final info = await services.engine.inspect(source.file);
      if (!mounted) return;
      _session?.dispose();
      _cache?.dispose();
      setState(() {
        _session = PageEditSession(pageCount: info.pageCount)
          ..addListener(_onSessionChanged);
        _cache = ThumbnailCache(engine: services.engine, file: source.file);
        _loading = false;
      });
    } on PdfFailure catch (failure) {
      if (mounted) {
        setState(() {
          _failure = failure;
          _loading = false;
          _source = null;
        });
      }
    }
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final services = AppServicesScope.of(context);
    final session = _session!;
    final source = _source!;
    final pages = session.pages;

    // Requirements.md 5.2: replacing is only offered for a document the app
    // owns, because a picked file is a copy and writing to it would change
    // nothing the user can see.
    var target = SaveTarget.newFile;
    if (source.canReplace) {
      final chosen = await askSaveTarget(
        context,
        documentName: source.displayName,
        changeSummary: '${pages.length} page'
            '${pages.length == 1 ? '' : 's'} after your edits.',
      );
      if (chosen == null || !mounted) return;
      target = chosen;
    }

    _job.run((handle) => savePageEdits(
          services: services,
          source: source,
          pages: pages,
          handle: handle,
          target: target,
          suffix: widget.tool.id == 'extract' ? 'extracted' : 'edited',
        ));
  }

  Future<bool> _confirmDiscard() async {
    final session = _session;
    if (session == null || !session.isDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Your edits have not been saved. Your original file is untouched '
          'either way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final running = _job.isRunning;

    return PopScope(
      canPop: session == null || !session.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            session == null || !session.hasSelection
                ? widget.tool.label
                : '${session.selectedCount} selected',
          ),
          actions: [
            if (session != null) ...[
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo',
                onPressed: running || !session.canUndo ? null : session.undo,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: 'Redo',
                onPressed: running || !session.canRedo ? null : session.redo,
              ),
              IconButton(
                icon: Icon(
                  session.selectedCount == session.pageCount
                      ? Icons.deselect
                      : Icons.select_all,
                ),
                tooltip: session.selectedCount == session.pageCount
                    ? 'Clear selection'
                    : 'Select all',
                onPressed: running
                    ? null
                    : () => session.selectedCount == session.pageCount
                        ? session.clearSelection()
                        : session.selectAll(),
              ),
            ],
          ],
        ),
        body: SafeArea(child: _body(session, running)),
        bottomNavigationBar:
            session == null ? null : _bottomBar(session, running),
      ),
    );
  }

  Widget _body(PageEditSession? session, bool running) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (session == null) {
      return ListView(
        padding: const EdgeInsets.all(Insets.lg),
        children: [
          if (_failure case final failure?)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.lg),
              child: FailureView(failure: failure),
            ),
          _ChooseCard(tool: widget.tool, onChoose: _choose),
        ],
      );
    }

    return Column(
      children: [
        if (_job.failure case final failure?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Insets.lg, Insets.lg, Insets.lg, 0),
            child: FailureView(failure: failure, onRetry: _save),
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
        Expanded(child: _grid(session, running)),
      ],
    );
  }

  Widget _grid(PageEditSession session, bool running) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= Insets.tabletBreakpoint => 5,
          >= Insets.largePhoneBreakpoint => 4,
          _ => 3,
        };
        final pages = session.pages;

        return ReorderableGridView(
          columns: columns,
          padding: const EdgeInsets.all(Insets.lg),
          itemCount: pages.length,
          enabled: !running,
          onReorder: session.move,
          itemBuilder: (context, index) {
            final page = pages[index];
            return PageTile(
              key: ValueKey(page.id),
              page: page,
              position: index + 1,
              selected: session.selection.contains(page.id),
              cache: _cache!,
              onTap: running ? () {} : () => session.toggle(page.id),
            );
          },
        );
      },
    );
  }

  Widget _bottomBar(PageEditSession session, bool running) {
    final theme = Theme.of(context);
    final enabled = session.hasSelection && !running;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
            Insets.sm, Insets.sm, Insets.sm, Insets.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Action(
                  icon: Icons.rotate_90_degrees_ccw_outlined,
                  label: 'Left',
                  onPressed: enabled ? () => session.rotateSelection(-1) : null,
                ),
                _Action(
                  icon: Icons.rotate_90_degrees_cw_outlined,
                  label: 'Right',
                  onPressed: enabled ? () => session.rotateSelection(1) : null,
                ),
                _Action(
                  icon: Icons.copy_all_outlined,
                  label: 'Duplicate',
                  onPressed: enabled ? session.duplicateSelection : null,
                ),
                _Action(
                  icon: Icons.content_copy_outlined,
                  label: 'Keep only',
                  onPressed: enabled ? () => session.extractSelection() : null,
                ),
                _Action(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onPressed: enabled && session.selectedCount < session.pageCount
                      ? () => session.deleteSelection()
                      : null,
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: running || !session.isDirty ? null : _save,
                  child: Text(
                    session.isDirty
                        ? 'Save ${session.pageCount} page'
                            '${session.pageCount == 1 ? '' : 's'}'
                        : 'No changes yet',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Corners.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outline,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChooseCard extends StatelessWidget {
  const _ChooseCard({required this.tool, required this.onChoose});

  final PdfTool tool;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
      child: Column(
        children: [
          Icon(tool.icon, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: Insets.lg),
          Text(tool.description, style: theme.textTheme.titleMedium),
          const SizedBox(height: Insets.xs),
          Text(
            'Rotate, reorder, duplicate, delete and extract pages together, '
            'then save once.',
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
