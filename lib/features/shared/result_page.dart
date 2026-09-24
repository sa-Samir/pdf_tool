import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/files/document_store.dart' show kRevisionMaxAge;
import '../../core/files/save_target.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../viewer/viewer_page.dart';
import 'job_views.dart';
import 'undo_replace.dart';

/// Puts back a replaced version. Injected so the card's states can be tested:
/// real file I/O never completes inside a widget test's fake-async zone.
typedef UndoAction = Future<void> Function(AppServices, ReplacedVersion);

/// What the user sees after an operation succeeds (requirements.md 6).
class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.title,
    required this.files,
    this.summary,
    this.undo,
    this.undoAction = undoReplace,
  });

  final String title;
  final List<File> files;

  /// One line of honest detail, e.g. "4 files from 27 pages".
  final String? summary;

  /// Set when this result replaced an existing document, so the previous
  /// version can be put back (requirements.md 5.2). Null when a new file was
  /// saved, which overwrote nothing and needs no undo.
  final ReplacedVersion? undo;

  /// How [undo] is carried out. The default does the real work; tests pass a
  /// stand-in so the offered → running → restored path can be exercised.
  final UndoAction undoAction;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  /// Bumped when the file on disk changes under us, so the size shown is the
  /// size of what is actually there now.
  var _revision = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = AppServicesScope.of(context);
    final undo = widget.undo;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Insets.lg),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Text(
                          widget.summary ??
                              '${widget.files.length} file'
                                  '${widget.files.length == 1 ? '' : 's'} saved',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (undo != null) ...[
                    const SizedBox(height: Insets.lg),
                    _UndoCard(
                      version: undo,
                      action: widget.undoAction,
                      onUndone: () => setState(() => _revision++),
                    ),
                  ],
                  const SizedBox(height: Insets.lg),
                  for (final file in widget.files)
                    _ResultTile(
                      key: ValueKey('${file.path}#$_revision'),
                      file: file,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => services.export.share(widget.files),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
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

/// Offers to put back the version this operation replaced.
///
/// Deliberately a card on the page rather than a snackbar: the previous version
/// survives for days, so throwing the only way to reach it away after a few
/// seconds would waste the thing that makes replacing safe.
class _UndoCard extends StatefulWidget {
  const _UndoCard({
    required this.version,
    required this.action,
    required this.onUndone,
  });

  final ReplacedVersion version;
  final UndoAction action;
  final VoidCallback onUndone;

  @override
  State<_UndoCard> createState() => _UndoCardState();
}

enum _UndoState { offered, running, done, failed }

class _UndoCardState extends State<_UndoCard> {
  var _state = _UndoState.offered;

  Future<void> _undo() async {
    final services = AppServicesScope.of(context);
    setState(() => _state = _UndoState.running);
    try {
      await widget.action(services, widget.version);
      if (!mounted) return;
      setState(() => _state = _UndoState.done);
      widget.onUndone();
    } on Object {
      // The new version is still in place and still usable, so there is
      // nothing to roll back -- only something to report.
      if (mounted) setState(() => _state = _UndoState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.version.documentName;
    final days = kRevisionMaxAge.inDays;

    final (IconData icon, String title, String subtitle) = switch (_state) {
      _UndoState.offered => (
          Icons.history,
          'Replaced $name',
          'The previous version is kept for $days days.',
        ),
      _UndoState.running => (
          Icons.history,
          'Putting it back...',
          'Restoring the previous version of $name.',
        ),
      _UndoState.done => (
          Icons.undo,
          'Previous version restored',
          '$name is back as it was.',
        ),
      _UndoState.failed => (
          Icons.error_outline,
          'Could not undo',
          'The previous version could not be put back. $name still holds the '
              'new content.',
        ),
    };

    return Card(
      color: _state == _UndoState.failed
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    maxLines: 3,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_state == _UndoState.offered) ...[
              const SizedBox(width: Insets.sm),
              TextButton(onPressed: _undo, child: const Text('Undo')),
            ],
            if (_state == _UndoState.running) ...[
              const SizedBox(width: Insets.sm),
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({super.key, required this.file});

  final File file;

  bool get _isPdf => p.extension(file.path).toLowerCase() == '.pdf';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Card(
        child: ListTile(
          onTap: _isPdf
              ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfViewerPage(file: file),
                    ),
                  )
              : null,
          trailing: _isPdf ? const Icon(Icons.chevron_right) : null,
          leading: Icon(
            Icons.picture_as_pdf_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            p.basename(file.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: FutureBuilder<int>(
            future: file.length(),
            builder: (context, snapshot) => Text(
              snapshot.hasData ? formatBytes(snapshot.data!) : '',
            ),
          ),
        ),
      ),
    );
  }
}
