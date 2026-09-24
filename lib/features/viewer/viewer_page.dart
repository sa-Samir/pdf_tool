import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/app_services.dart';
import '../shared/print_document.dart';
import '../../core/theme/app_theme.dart';
import '../shared/job_views.dart';
import 'viewer_controller.dart';
import 'widgets/viewer_page_view.dart';

/// The document viewer (requirements.md 3.2).
class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({super.key, required this.file, this.title});

  final File file;
  final String? title;

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  final _scroll = ScrollController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();

  ViewerController? _controller;
  bool _searchOpen = false;
  int _visiblePage = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = ViewerController(
      engine: AppServicesScope.of(context).engine,
      file: widget.file,
    )..addListener(_onChanged);
    _controller!.open();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    _controller
      ?..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Tracks which page is in view, for the page indicator.
  void _onScroll() {
    final controller = _controller;
    if (controller == null || controller.pageCount == 0) return;
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
    final progress = _scroll.offset / _scroll.position.maxScrollExtent;
    final page = (progress * (controller.pageCount - 1)).round();
    if (page != _visiblePage) setState(() => _visiblePage = page.clamp(0, controller.pageCount - 1));
  }

  void _jumpTo(int pageIndex) {
    final controller = _controller;
    if (controller == null || !_scroll.hasClients) return;
    final fraction = controller.pageCount <= 1
        ? 0.0
        : pageIndex / (controller.pageCount - 1);
    _scroll.animateTo(
      fraction * _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _showJumpDialog() async {
    final controller = _controller!;
    final field = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Page number',
            hintText: '1 to ${controller.pageCount}',
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(field.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    field.dispose();
    if (page == null) return;
    _jumpTo((page - 1).clamp(0, controller.pageCount - 1));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final title = widget.title ?? p.basename(widget.file.path);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (controller?.status == ViewerStatus.ready) ...[
            IconButton(
              icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
              tooltip: _searchOpen ? 'Close search' : 'Search',
              onPressed: () {
                setState(() => _searchOpen = !_searchOpen);
                if (!_searchOpen) {
                  _searchController.clear();
                  controller!.clearSearch();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Print',
              // The page count is already known here, so the print preview
              // can show the real number rather than "unknown".
              onPressed: () => printDocument(
                context,
                widget.file,
                pageCount: controller!.pageCount,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: () =>
                  AppServicesScope.of(context).export.share([widget.file]),
            ),
          ],
        ],
      ),
      body: SafeArea(child: _body(controller)),
      bottomNavigationBar: controller?.status == ViewerStatus.ready
          ? _pageBar(controller!)
          : null,
    );
  }

  Widget _body(ViewerController? controller) {
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return switch (controller.status) {
      ViewerStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      ViewerStatus.needsPassword ||
      ViewerStatus.wrongPassword =>
        _passwordGate(controller),
      ViewerStatus.failed => Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: FailureView(
            failure: controller.failure!,
            onRetry: () => controller.open(),
          ),
        ),
      ViewerStatus.ready => Column(
          children: [
            if (_searchOpen) _searchBar(controller),
            Expanded(child: _pages(controller)),
          ],
        ),
    };
  }

  Widget _pages(ViewerController controller) {
    final current = controller.currentHit >= 0
        ? controller.hits[controller.currentHit]
        : null;

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(Insets.md),
      itemCount: controller.pageCount,
      itemBuilder: (context, index) => ViewerPageView(
        key: ValueKey(index),
        pageIndex: index,
        geometry: controller.geometry[index],
        cache: controller.pages!,
        hits: controller.hitsOn(index),
        currentHit: current?.pageIndex == index ? current : null,
      ),
    );
  }

  Widget _searchBar(ViewerController controller) {
    final theme = Theme.of(context);
    final hits = controller.hits;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Find in document',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: controller.searching
                    ? const Padding(
                        padding: EdgeInsets.all(Insets.md),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onSubmitted: controller.search,
            ),
          ),
          if (controller.hasSearch && !controller.searching) ...[
            const SizedBox(width: Insets.sm),
            Text(
              hits.isEmpty
                  ? 'No matches'
                  : '${controller.currentHit + 1} of ${hits.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
              onPressed: hits.isEmpty
                  ? null
                  : () {
                      final page = controller.previousHit();
                      if (page != null) _jumpTo(page);
                    },
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
              onPressed: hits.isEmpty
                  ? null
                  : () {
                      final page = controller.nextHit();
                      if (page != null) _jumpTo(page);
                    },
            ),
          ],
        ],
      ),
    );
  }

  Widget _passwordGate(ViewerController controller) {
    final theme = Theme.of(context);
    final wrong = controller.status == ViewerStatus.wrongPassword;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: Insets.lg),
              Text(
                'This PDF is password-protected.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Insets.lg),
              TextField(
                controller: _passwordController,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: wrong ? "That password didn't work." : null,
                ),
                onSubmitted: (value) => controller.open(password: value),
              ),
              const SizedBox(height: Insets.lg),
              FilledButton(
                onPressed: () =>
                    controller.open(password: _passwordController.text),
                child: const Text('Open'),
              ),
              const SizedBox(height: Insets.md),
              Text(
                'The password is used to open this document and is never '
                'saved.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageBar(ViewerController controller) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Page ${_visiblePage + 1} of ${controller.pageCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton.icon(
              onPressed: _showJumpDialog,
              icon: const Icon(Icons.numbers, size: 18),
              label: const Text('Go to page'),
            ),
          ],
        ),
      ),
    );
  }
}
