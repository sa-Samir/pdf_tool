import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engine/pdf_engine.dart';
import '../engine/pdf_failure.dart';

/// How long a replaced document's previous version is kept before the launch
/// prune removes it, and how many are kept at once. Long enough to change your
/// mind the next day; bounded so the revisions directory cannot grow without
/// limit (requirements.md 5.2).
const kRevisionMaxAge = Duration(days: 7);
const kRevisionsKept = 20;

/// A document that was replaced in place, and the content it held before.
class Replacement {
  const Replacement({required this.file, required this.previous});

  /// The document, now holding the new content. Same path as before.
  final File file;

  /// What it held before, waiting in the revisions directory.
  final File previous;
}

/// A scratch directory for one operation. Everything written here is temporary
/// and is deleted when the operation ends, however it ends.
class Workspace {
  Workspace(this.directory);

  final Directory directory;

  File file(String name) => File(p.join(directory.path, name));

  Future<void> dispose() async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // A workspace we cannot delete now is swept at next launch.
    }
  }
}

/// Owns where files live and enforces the data-integrity invariants in
/// requirements.md 5.2.
///
/// The important one: output is written to a workspace, verified as a readable
/// PDF, and only then moved into place. A failed operation leaves the original
/// untouched and nothing half-written behind.
class DocumentStore {
  DocumentStore({
    required PdfEngine engine,
    Future<Directory> Function()? documentsRoot,
    Future<Directory> Function()? tempRoot,
  })  : _engine = engine,
        _documentsRoot = documentsRoot ?? getApplicationDocumentsDirectory,
        _tempRoot = tempRoot ?? getTemporaryDirectory;

  final PdfEngine _engine;
  final Future<Directory> Function() _documentsRoot;
  final Future<Directory> Function() _tempRoot;

  static const _workspacePrefix = 'work-';

  Future<Directory> outputs() async => _ensure(await _documentsRoot(), 'documents');
  Future<Directory> imports() async => _ensure(await _documentsRoot(), 'imports');

  /// Where exported images land. Not the document library: those are PDFs.
  Future<Directory> exports() async => _ensure(await _documentsRoot(), 'exports');

  /// Where the previous version of a replaced document waits, so the replace
  /// can be undone (requirements.md 5.2).
  Future<Directory> revisions() async =>
      _ensure(await _documentsRoot(), 'revisions');

  Future<Workspace> openWorkspace() async {
    final root = _ensure(await _tempRoot(), 'workspaces');
    final id = '${DateTime.now().millisecondsSinceEpoch}'
        '-${Random().nextInt(1 << 32).toRadixString(16)}';
    final dir = Directory(p.join(root.path, '$_workspacePrefix$id'))
      ..createSync(recursive: true);
    return Workspace(dir);
  }

  /// Deletes workspaces left behind by a crash (requirements.md 5.2).
  /// Called at launch, not during an operation.
  Future<void> sweepWorkspaces() async {
    final root = _ensure(await _tempRoot(), 'workspaces');
    await for (final entity in root.list()) {
      if (entity is Directory &&
          p.basename(entity.path).startsWith(_workspacePrefix)) {
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          // Skip; it will be retried next launch.
        }
      }
    }
  }

  /// Verifies [temp] and moves it into the documents directory.
  ///
  /// Verification is the point: a file that cannot be reopened, or that has the
  /// wrong page count, never reaches the user's library.
  Future<File> commit(
    File temp, {
    required String desiredName,
    int? expectedPages,
  }) async {
    await _verify(temp, expectedPages: expectedPages);
    return _moveInto(temp, await _uniqueTarget(desiredName));
  }

  /// Puts [temp] in [target]'s place, keeping what was there
  /// (requirements.md 5.2).
  ///
  /// Verified first, then swapped, so an interrupted replace leaves the
  /// original intact rather than a half-written file where the user's document
  /// used to be. The previous version is kept in [revisions] and returned, so
  /// replacing is reversible rather than final. Only ever called on a file the
  /// app owns.
  Future<Replacement> replace(
    File temp, {
    required File target,
    int? expectedPages,
  }) async {
    await _verify(temp, expectedPages: expectedPages);

    // Copied rather than moved. Moving would leave the document missing from
    // its own path for as long as the swap takes, and a crash inside that
    // window would leave a library entry pointing at nothing -- which the
    // launch prune would then delete. One extra pass over the file buys
    // "the original survives any failure" by construction.
    final backup = await _unique(await revisions(), p.basename(target.path));
    await target.copy(backup.path);

    try {
      return Replacement(
        file: await _moveInto(temp, target),
        previous: backup,
      );
    } catch (_) {
      await _deleteQuietly(backup);
      rethrow;
    }
  }

  /// Puts the previous version of a replaced document back.
  ///
  /// Deliberately not verified. [_verify] guards output this app just produced;
  /// a revision is content that was already in the library, and refusing to
  /// restore it would strand the user with the version they asked to undo.
  /// One-shot: the revision is consumed, so a second undo has nothing to do.
  Future<File> restore(Replacement replacement) =>
      _moveInto(replacement.previous, replacement.file);

  /// Drops revisions older than [maxAge], then keeps only the newest [keep]
  /// (requirements.md 5.2). Called at launch, never during an operation.
  Future<void> pruneRevisions({
    Duration maxAge = kRevisionMaxAge,
    int keep = kRevisionsKept,
  }) async {
    final dir = await revisions();
    final dated = <({DateTime at, File file})>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        dated.add((at: await entity.lastModified(), file: entity));
      } on FileSystemException {
        // Vanished between listing and stat; nothing left to prune.
      }
    }
    final cutoff = DateTime.now().subtract(maxAge);
    dated.sort((a, b) => b.at.compareTo(a.at)); // newest first
    for (var i = 0; i < dated.length; i++) {
      if (i >= keep || dated[i].at.isBefore(cutoff)) {
        await _deleteQuietly(dated[i].file);
      }
    }
  }

  /// Moves [temp] onto [target], falling back to a copy across volumes.
  static Future<File> _moveInto(File temp, File target) async {
    try {
      return await temp.rename(target.path);
    } on FileSystemException {
      final copied = await temp.copy(target.path);
      await _deleteQuietly(temp);
      return copied;
    }
  }

  /// Copies an imported file into the sandbox (requirements.md 3.3). Picked
  /// URLs are temporary on iOS and revocable on Android, so the copy is what we
  /// operate on and what history points at.
  Future<File> adoptImport(File source, String displayName) async {
    final dir = await imports();
    final target = await _unique(dir, displayName);
    return source.copy(target.path);
  }

  /// Refuses a result that cannot be reopened or has the wrong page count,
  /// and removes it, so a bad output never reaches the user either way.
  Future<void> _verify(File temp, {int? expectedPages}) async {
    final PdfDocumentInfo info;
    try {
      info = await _engine.inspect(temp);
    } on PdfFailure catch (failure) {
      await _deleteQuietly(temp);
      // A result we cannot reopen is our bug, not a damaged input.
      throw PdfFailure(FailureKind.unknown, cause: failure.cause ?? failure);
    }
    if (expectedPages != null && info.pageCount != expectedPages) {
      await _deleteQuietly(temp);
      throw PdfFailure(
        FailureKind.unknown,
        detail: 'expected $expectedPages pages, produced ${info.pageCount}',
      );
    }
  }

  Future<File> _uniqueTarget(String desiredName) async =>
      _unique(await outputs(), desiredName);

  Future<File> _unique(Directory dir, String desiredName) async {
    final name = sanitizeFileName(desiredName);
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var candidate = File(p.join(dir.path, name));
    var counter = 2;
    while (await candidate.exists()) {
      candidate = File(p.join(dir.path, '$stem ($counter)$ext'));
      counter++;
    }
    return candidate;
  }

  static Directory _ensure(Directory base, String child) {
    final dir = Directory(p.join(base.path, child));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Nothing useful to do; the workspace sweep will catch it.
    }
  }
}

/// Strips separators and characters the platforms reject, and keeps the result
/// inside the 255-byte limit both filesystems enforce.
String sanitizeFileName(String name) {
  var cleaned = name
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') cleaned = 'document';

  final ext = p.extension(cleaned);
  var stem = p.basenameWithoutExtension(cleaned);
  const maxBytes = 200;
  while (stem.isNotEmpty && '$stem$ext'.codeUnits.length > maxBytes) {
    stem = stem.substring(0, stem.length - 1);
  }
  if (stem.isEmpty) stem = 'document';
  return '$stem$ext';
}
