import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/library/library_document.dart';
import '../../core/catalog/tool_catalog.dart';
import '../../core/files/save_target.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../shared/job_views.dart';
import '../shared/save_to_device.dart';
import '../compress/compress_page.dart';
import '../pages/page_grid_page.dart';
import '../viewer/viewer_page.dart';

/// The files the app has produced (requirements.md 4 and 5.1).
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.highlightId, this.folder});

  /// Scrolled to and briefly emphasised, when arriving from a recents tile.
  final String? highlightId;

  /// When set, the page shows one folder's contents (requirements.md 5.1).
  final LibraryFolder? folder;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _searchController = TextEditingController();
  Future<List<LibraryDocument>>? _documents;
  Future<List<LibraryFolder>>? _folders;
  LibrarySort _sort = LibrarySort.newest;
  bool _favouritesOnly = false;
  String _query = '';

  /// Ids picked for a bulk action. Empty means normal browsing: selection mode
  /// is a state the list enters by long-press, not a mode toggle to find.
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_documents == null) _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Searching looks everywhere; browsing stays where the user is.
  FolderScope get _scope {
    if (_query.trim().isNotEmpty || _favouritesOnly) {
      return FolderScope.everywhere;
    }
    final folder = widget.folder;
    return folder == null ? FolderScope.root : FolderScope.inside(folder.id);
  }

  Future<List<LibraryDocument>> _load() =>
      AppServicesScope.of(context).library.list(
            sort: _sort,
            query: _query,
            favouritesOnly: _favouritesOnly,
            scope: _scope,
          );

  void _reload() => setState(() {
        _documents = _load();
        _folders = widget.folder == null
            ? AppServicesScope.of(context).library.folders()
            : Future.value(const <LibraryFolder>[]);
      });

  /// Copies one document out of the sandbox (requirements.md 6).
  Future<void> _saveToDevice(LibraryDocument document) async {
    final services = AppServicesScope.of(context);
    final file = await services.library.fileFor(document);
    if (!mounted) return;
    if (file == null) {
      _reportMissing();
      return;
    }
    await saveToDevice(context, [file]);
  }

  /// Copies everything selected out in one go, which is the case that actually
  /// protects someone against losing the library to an uninstall.
  Future<void> _saveSelectedToDevice() async {
    final services = AppServicesScope.of(context);
    final files = <File>[];
    for (final id in _selected) {
      final document = await services.library.byId(id);
      if (document == null) continue;
      final file = await services.library.fileFor(document);
      if (file != null) files.add(file);
    }
    if (!mounted) return;
    if (files.isEmpty) {
      _reportMissing();
      return;
    }
    await saveToDevice(context, files);
    if (mounted) setState(_selected.clear);
  }

  void _toggleSelected(LibraryDocument document) => setState(() {
        if (!_selected.remove(document.id)) _selected.add(document.id);
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
    final navigator = Navigator.of(context);
    final file = await services.library.fileFor(document);
    if (file == null) {
      _reportMissing();
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerPage(file: file, title: document.name),
      ),
    );
    if (mounted) _reload();
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

  Future<void> _newFolder() async {
    final name = await _askForName(title: 'New folder');
    if (name == null || !mounted) return;
    final library = AppServicesScope.of(context).library;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await library.createFolder(name);
    } on StateError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (mounted) _reload();
  }

  Future<void> _renameFolder(LibraryFolder folder) async {
    final name =
        await _askForName(title: 'Rename folder', initial: folder.name);
    if (name == null || !mounted) return;
    final library = AppServicesScope.of(context).library;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await library.renameFolder(folder.id, name);
    } on StateError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (mounted) _reload();
  }

  Future<void> _deleteFolder(LibraryFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${folder.name}?'),
        content: const Text(
          'The folder goes; the files in it stay and move back to Files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppServicesScope.of(context).library.deleteFolder(folder.id);
    if (mounted) _reload();
  }

  /// Opens a tool on a document the app owns, which is what makes replacing
  /// the original possible at all (requirements.md 5.2).
  Future<void> _editWith(LibraryDocument document, String toolId) async {
    final services = AppServicesScope.of(context);
    final navigator = Navigator.of(context);
    final file = await services.library.fileFor(document);
    if (file == null) {
      _reportMissing();
      return;
    }
    final source = EditableSource.owned(document, file);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => toolId == 'compress'
            ? CompressPage(source: source)
            : PageGridPage(
                tool: ToolCatalog.all.firstWhere((t) => t.id == 'reorder'),
                source: source,
              ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _move(LibraryDocument document) async {
    final library = AppServicesScope.of(context).library;
    final folders = await library.folders();
    if (!mounted) return;

    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(Insets.lg),
              child: Text('Move to'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('Files (no folder)'),
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final folder in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () => Navigator.of(context).pop(folder.id),
              ),
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Insets.lg),
                child: Text('Make a folder first to file things away.'),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await library.moveToFolder(document.id, target.isEmpty ? null : target);
    if (mounted) _reload();
  }

  Future<void> _openFolder(LibraryFolder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LibraryPage(folder: folder)),
    );
    if (mounted) _reload();
  }

  Future<String?> _askForName({required String title, String? initial}) =>
      showDialog<String>(
        context: context,
        builder: (context) => _NameDialog(title: title, initialName: initial),
      );

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
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: () => setState(_selected.clear),
              ),
              title: Text('${_selected.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.save_alt),
                  tooltip: 'Save selected to device',
                  onPressed: _saveSelectedToDevice,
                ),
              ],
            )
          : AppBar(
              title: Text(widget.folder?.name ?? 'Files'),
              actions: [
                if (widget.folder == null)
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'New folder',
                    onPressed: _newFolder,
                  ),
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
                  return FutureBuilder<List<LibraryFolder>>(
                    future: _folders,
                    builder: (context, folderSnapshot) {
                      final folders =
                          folderSnapshot.data ?? const <LibraryFolder>[];
                      if (documents.isEmpty && folders.isEmpty) {
                        return _EmptyLibrary(
                          searching: _query.trim().isNotEmpty,
                          favouritesOnly: _favouritesOnly,
                          inFolder: widget.folder != null,
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(
                            Insets.lg, 0, Insets.lg, Insets.xxl),
                        children: [
                          for (final folder in folders) ...[
                            _FolderTile(
                              folder: folder,
                              onOpen: () => _openFolder(folder),
                              onRename: () => _renameFolder(folder),
                              onDelete: () => _deleteFolder(folder),
                            ),
                            const SizedBox(height: Insets.sm),
                          ],
                          for (final document in documents) ...[
                            _DocumentTile(
                              document: document,
                              highlighted: document.id == widget.highlightId,
                              selecting: _selecting,
                              selected: _selected.contains(document.id),
                              onToggleSelected: () =>
                                  _toggleSelected(document),
                              onSaveToDevice: () => _saveToDevice(document),
                              onOpen: () => _open(document),
                              onShare: () => _share(document),
                              onRename: () => _rename(document),
                              onDelete: () => _delete(document),
                              onMove: () => _move(document),
                              onEditPages: () =>
                                  _editWith(document, 'reorder'),
                              onCompress: () =>
                                  _editWith(document, 'compress'),
                              onToggleFavorite: () =>
                                  _toggleFavorite(document),
                            ),
                            const SizedBox(height: Insets.sm),
                          ],
                        ],
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
    required this.selecting,
    required this.selected,
    required this.onToggleSelected,
    required this.onSaveToDevice,
    required this.onOpen,
    required this.onShare,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.onEditPages,
    required this.onCompress,
    required this.onToggleFavorite,
  });

  final LibraryDocument document;
  final bool highlighted;

  /// True while the list is picking documents for a bulk action.
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback onSaveToDevice;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onEditPages;
  final VoidCallback onCompress;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = document.pageCount;

    return Card(
      color: switch ((selected, highlighted)) {
        (true, _) => theme.colorScheme.secondaryContainer,
        (_, true) => theme.colorScheme.primaryContainer,
        _ => null,
      },
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        // Long-press starts a selection; once one is running, a plain tap
        // adds to it rather than opening the document out from under it.
        onTap: selecting ? onToggleSelected : onOpen,
        onLongPress: onToggleSelected,
        leading: Icon(
          selecting
              ? (selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked)
              : Icons.picture_as_pdf_outlined,
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
        trailing: selecting
            ? null
            : Row(
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
                      'pages' => onEditPages(),
                      'compress' => onCompress(),
                      'save' => onSaveToDevice(),
                      'share' => onShare(),
                      'rename' => onRename(),
                      'move' => onMove(),
                      'delete' => onDelete(),
                      _ => null,
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'pages', child: Text('Edit pages')),
                      PopupMenuItem(value: 'compress', child: Text('Compress')),
                      PopupMenuDivider(),
                      PopupMenuItem(
                          value: 'save', child: Text('Save to device')),
                      PopupMenuItem(value: 'share', child: Text('Share')),
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'move', child: Text('Move to folder')),
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
  const _EmptyLibrary({
    required this.searching,
    required this.favouritesOnly,
    this.inFolder = false,
  });

  final bool searching;
  final bool favouritesOnly;
  final bool inFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, detail) = switch ((searching, favouritesOnly, inFolder)) {
      (true, _, _) => ('Nothing matches that', 'Try a different name.'),
      (false, true, _) => (
          'No favourites yet',
          'Tap the star on a file to keep it here.',
        ),
      (false, false, true) => (
          'This folder is empty',
          'Move files here from the Files list.',
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

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryFolder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = folder.documentCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        leading: Icon(Icons.folder, color: theme.colorScheme.primary),
        title: Text(
          folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          count == 0 ? 'Empty' : '$count file${count == 1 ? '' : 's'}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'More actions for ${folder.name}',
          onSelected: (value) => switch (value) {
            'rename' => onRename(),
            'delete' => onDelete(),
            _ => null,
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete folder')),
          ],
        ),
      ),
    );
  }
}

/// Owns its controller so it is disposed with the dialog, not during teardown.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initialName});

  final String title;
  final String? initialName;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
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
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Folder name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
