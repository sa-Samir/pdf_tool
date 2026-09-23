
import 'package:flutter/material.dart';

import '../../core/library/library_document.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../shared/job_views.dart';

/// The files the app has produced (requirements.md 4 and 5.1).
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.highlightId});

  /// Scrolled to and briefly emphasised, when arriving from a recents tile.
  final String? highlightId;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _searchController = TextEditingController();
  Future<List<LibraryDocument>>? _documents;
  LibrarySort _sort = LibrarySort.newest;
  bool _favouritesOnly = false;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _documents ??= _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<LibraryDocument>> _load() {
    final library = AppServicesScope.of(context).library;
    return library.list(
      sort: _sort,
      query: _query,
      favouritesOnly: _favouritesOnly,
    );
  }

  void _reload() => setState(() {
        _documents = _load();
      });

  Future<void> _share(LibraryDocument document) async {
    final services = AppServicesScope.of(context);
    final file = await services.library.fileFor(document);
    if (file == null) {
      _reportMissing();
      return;
    }
    await services.export.share([file]);
  }

  Future<void> _open(LibraryDocument document) async {
    final services = AppServicesScope.of(context);
    final file = await services.library.fileFor(document);
    if (file == null) {
      _reportMissing();
      return;
    }
    // Opening in a reader is the platform's job until the viewer lands.
    await services.export.share([file]);
  }

  void _reportMissing() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('That file is no longer on this device.')),
      );
    _reload();
  }

  Future<void> _rename(LibraryDocument document) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: document.name),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    final library = AppServicesScope.of(context).library;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await library.rename(document.id, name.trim());
    } on StateError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (mounted) _reload();
  }

  Future<void> _delete(LibraryDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${document.name}?'),
        content: const Text(
          'This deletes the file from this app. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppServicesScope.of(context).library.delete(document.id);
    if (mounted) _reload();
  }

  Future<void> _toggleFavorite(LibraryDocument document) async {
    await AppServicesScope.of(context)
        .library
        .setFavorite(document.id, !document.favorite);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            icon: Icon(_favouritesOnly ? Icons.star : Icons.star_border),
            tooltip: _favouritesOnly ? 'Show all' : 'Favourites only',
            onPressed: () {
              setState(() => _favouritesOnly = !_favouritesOnly);
              _reload();
            },
          ),
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: (value) {
              setState(() => _sort = value);
              _reload();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: LibrarySort.newest, child: Text('Newest')),
              PopupMenuItem(value: LibrarySort.name, child: Text('Name')),
              PopupMenuItem(value: LibrarySort.size, child: Text('Size')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.lg, Insets.sm, Insets.lg, Insets.sm),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search files',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                            _reload();
                          },
                        ),
                ),
                onChanged: (value) {
                  setState(() => _query = value);
                  _reload();
                },
              ),
            ),
            Expanded(
              child: FutureBuilder<List<LibraryDocument>>(
                future: _documents,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final documents = snapshot.data ?? const <LibraryDocument>[];
                  if (documents.isEmpty) {
                    return _EmptyLibrary(
                      searching: _query.trim().isNotEmpty,
                      favouritesOnly: _favouritesOnly,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        Insets.lg, 0, Insets.lg, Insets.xxl),
                    itemCount: documents.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Insets.sm),
                    itemBuilder: (context, i) {
                      final document = documents[i];
                      return _DocumentTile(
                        document: document,
                        highlighted: document.id == widget.highlightId,
                        onOpen: () => _open(document),
                        onShare: () => _share(document),
                        onRename: () => _rename(document),
                        onDelete: () => _delete(document),
                        onToggleFavorite: () => _toggleFavorite(document),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              child: Text(
                'These files live in this app on this device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: Insets.sm),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.highlighted,
    required this.onOpen,
    required this.onShare,
    required this.onRename,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final LibraryDocument document;
  final bool highlighted;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = document.pageCount;

    return Card(
      color: highlighted ? theme.colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        leading: Icon(
          Icons.picture_as_pdf_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${document.operation} · '
          '${pages == null ? '' : '$pages page${pages == 1 ? '' : 's'} · '}'
          '${formatBytes(document.sizeBytes)} · '
          '${formatRelativeTime(document.createdAt)}',
          maxLines: 2,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                document.favorite ? Icons.star : Icons.star_border,
                color: document.favorite ? theme.colorScheme.primary : null,
              ),
              tooltip: document.favorite
                  ? 'Remove ${document.name} from favourites'
                  : 'Add ${document.name} to favourites',
              onPressed: onToggleFavorite,
            ),
            PopupMenuButton<String>(
              tooltip: 'More actions for ${document.name}',
              onSelected: (value) => switch (value) {
                'share' => onShare(),
                'rename' => onRename(),
                'delete' => onDelete(),
                _ => null,
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.searching, required this.favouritesOnly});

  final bool searching;
  final bool favouritesOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, detail) = switch ((searching, favouritesOnly)) {
      (true, _) => ('Nothing matches that', 'Try a different name.'),
      (false, true) => (
          'No favourites yet',
          'Tap the star on a file to keep it here.',
        ),
      _ => (
          'No files yet',
          'Anything you merge, split or edit is saved here.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.folder_open_outlined,
              size: 40,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: Insets.md),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: Insets.xs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns its own text controller so it is disposed with the dialog, not while
/// the dialog is still being torn down.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }
}
