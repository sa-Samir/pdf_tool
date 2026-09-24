import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../entitlements/sqflite_entitlements.dart';
import '../files/document_store.dart';
import 'library_document.dart';
import 'library_repository.dart';

/// The library, in a local SQLite database (requirements.md 17).
///
/// Local only: nothing here is synced, and the database lives beside the
/// documents it describes.
class SqfliteLibraryRepository implements LibraryRepository {
  SqfliteLibraryRepository({
    required DocumentStore store,
    required FutureOr<Database> database,
    this.retention = const RetentionPolicy(),
  })  : _store = store,
        _db = Future.value(database);

  final DocumentStore _store;

  /// Held as a future so opening the database never blocks startup: the home
  /// screen must be interactive before any database work finishes
  /// (requirements.md 3.1).
  final Future<Database> _db;
  final RetentionPolicy retention;

  static const _table = 'documents';
  static const _folders = 'folders';

  /// Bumped whenever the schema changes; [migrate] handles the upgrade.
  ///   1 -- documents
  ///   2 -- folders, and documents.folder_id
  ///   3 -- tool_usage, for the free-tier counts
  static const schemaVersion = 3;

  /// Opens (and migrates) the database at [path].
  ///
  /// Tests swap sqflite's global `databaseFactory` for the FFI one, so this
  /// same call works on a device and in a plain Dart test.
  static Future<Database> open(String path) => openDatabase(
        path,
        version: schemaVersion,
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: migrate,
      );

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $_table (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        page_count INTEGER,
        operation TEXT NOT NULL,
        tool_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        favorite INTEGER NOT NULL DEFAULT 0,
        folder_id TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_documents_created_at ON $_table (created_at DESC)',
    );
    await _createFolderTable(db);
    await SqfliteEntitlements.createSchema(db);
  }

  static Future<void> _createFolderTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// Schema upgrades, applied one version at a time so a device two versions
  /// behind arrives at the same place as one that was only one behind.
  static Future<void> migrate(Database db, int from, int to) async {
    for (var version = from; version < to; version++) {
      switch (version) {
        case 1:
          await _createFolderTable(db);
          await db.execute('ALTER TABLE $_table ADD COLUMN folder_id TEXT');
        case 2:
          await SqfliteEntitlements.createSchema(db);
      }
    }
  }

  @override
  Future<List<LibraryDocument>> list({
    LibrarySort sort = LibrarySort.newest,
    String query = '',
    bool favouritesOnly = false,
    int limit = 0,
    FolderScope scope = FolderScope.everywhere,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (favouritesOnly) where.add('favorite = 1');
    switch (scope) {
      case FolderScopeRoot():
        where.add('folder_id IS NULL');
      case FolderScopeInside(:final folderId):
        where.add('folder_id = ?');
        args.add(folderId);
      case FolderScopeEverywhere():
        break;
    }
    if (query.trim().isNotEmpty) {
      where.add('name LIKE ? ESCAPE ?');
      args
        ..add('%${_escapeLike(query.trim())}%')
        ..add(r'\');
    }

    final rows = await (await _db).query(
      _table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: switch (sort) {
        LibrarySort.newest => 'created_at DESC',
        LibrarySort.name => 'name COLLATE NOCASE ASC',
        LibrarySort.size => 'size_bytes DESC',
      },
      limit: limit == 0 ? null : limit,
    );
    return [for (final row in rows) LibraryDocument.fromRow(row)];
  }

  @override
  Future<List<LibraryFolder>> folders() async {
    final rows = await (await _db).query(_folders, orderBy: 'created_at ASC');
    final counts = await (await _db).rawQuery(
      'SELECT folder_id, COUNT(*) AS n FROM $_table '
      'WHERE folder_id IS NOT NULL GROUP BY folder_id',
    );
    final byFolder = {
      for (final row in counts) row['folder_id'] as String: row['n']! as int,
    };
    return [
      for (final row in rows)
        LibraryFolder.fromRow(row, count: byFolder[row['id']] ?? 0),
    ];
  }

  @override
  Future<LibraryFolder> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('a folder needs a name');
    final existing = await folders();
    if (existing.any((f) => f.name.toLowerCase() == trimmed.toLowerCase())) {
      throw StateError('there is already a folder called $trimmed');
    }
    final folder = LibraryFolder(
      id: '${DateTime.now().microsecondsSinceEpoch}-${trimmed.hashCode}',
      name: trimmed,
      createdAt: DateTime.now(),
    );
    await (await _db).insert(_folders, folder.toRow());
    return folder;
  }

  @override
  Future<LibraryFolder> renameFolder(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('a folder needs a name');
    final all = await folders();
    final folder = all.where((f) => f.id == id).firstOrNull;
    if (folder == null) throw StateError('no folder $id');
    if (all.any((f) =>
        f.id != id && f.name.toLowerCase() == trimmed.toLowerCase())) {
      throw StateError('there is already a folder called $trimmed');
    }
    final renamed = folder.copyWith(name: trimmed);
    await (await _db)
        .update(_folders, renamed.toRow(), where: 'id = ?', whereArgs: [id]);
    return renamed;
  }

  @override
  Future<void> deleteFolder(String id) async {
    // The documents move out rather than going with it: deleting a folder is
    // not a way to delete files by accident (requirements.md 5.2).
    await (await _db).update(
      _table,
      {'folder_id': null},
      where: 'folder_id = ?',
      whereArgs: [id],
    );
    await (await _db).delete(_folders, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> moveToFolder(String documentId, String? folderId) async {
    await (await _db).update(
      _table,
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  @override
  Future<LibraryDocument?> byId(String id) async {
    final rows = await (await _db).query(_table, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : LibraryDocument.fromRow(rows.first);
  }

  @override
  Future<LibraryDocument> record({
    required File file,
    required String operation,
    required String toolId,
    int? pageCount,
  }) async {
    final outputs = await _store.outputs();
    final document = LibraryDocument(
      id: '${DateTime.now().microsecondsSinceEpoch}-${file.hashCode}',
      name: p.basename(file.path),
      relativePath: p.relative(file.path, from: outputs.path),
      sizeBytes: await file.length(),
      pageCount: pageCount,
      operation: operation,
      toolId: toolId,
      createdAt: DateTime.now(),
    );
    await (await _db).insert(_table, document.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _applyRetention();
    return document;
  }

  @override
  Future<LibraryDocument> rename(String id, String name) async {
    final existing = await byId(id);
    if (existing == null) {
      throw StateError('no library document $id');
    }
    final safeName = sanitizeFileName(
      p.extension(name).isEmpty ? '$name.pdf' : name,
    );
    final file = await fileFor(existing);
    var relativePath = existing.relativePath;

    if (file != null) {
      final target = File(p.join(file.parent.path, safeName));
      if (target.path != file.path) {
        if (await target.exists()) {
          throw StateError('a file called $safeName is already here');
        }
        final moved = await file.rename(target.path);
        final outputs = await _store.outputs();
        relativePath = p.relative(moved.path, from: outputs.path);
      }
    }

    final updated = existing.copyWith(name: safeName, relativePath: relativePath);
    await (await _db).update(_table, updated.toRow(), where: 'id = ?', whereArgs: [id]);
    return updated;
  }

  @override
  Future<void> setFavorite(String id, bool favorite) async {
    await (await _db).update(
      _table,
      {'favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> delete(String id, {bool deleteFile = true}) async {
    final existing = await byId(id);
    if (existing != null && deleteFile) {
      final file = await fileFor(existing);
      await _deleteQuietly(file);
    }
    await (await _db).delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<File?> fileFor(LibraryDocument document) async {
    final outputs = await _store.outputs();
    final file = File(p.join(outputs.path, document.relativePath));
    return await file.exists() ? file : null;
  }

  @override
  Future<int> pruneMissing() async {
    final all = await list();
    var removed = 0;
    for (final document in all) {
      if (await fileFor(document) == null) {
        await (await _db).delete(_table, where: 'id = ?', whereArgs: [document.id]);
        removed++;
      }
    }
    return removed;
  }

  @override
  Future<void> clearAll() async {
    for (final document in await list()) {
      await _deleteQuietly(await fileFor(document));
    }
    await (await _db).delete(_table);
    await (await _db).delete(_folders);
  }

  /// Requirements.md 4: keep the last N, and nothing older than the max age.
  /// Favourites are exempt -- the user said those matter.
  Future<void> _applyRetention() async {
    final cutoff = DateTime.now().subtract(retention.maxAge);
    final expired = await (await _db).query(
      _table,
      where: 'favorite = 0 AND created_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
    for (final row in expired) {
      await delete(row['id']! as String);
    }

    final surplus = await (await _db).query(
      _table,
      where: 'favorite = 0',
      orderBy: 'created_at DESC',
      limit: 1 << 30,
      offset: retention.maxEntries,
    );
    for (final row in surplus) {
      await delete(row['id']! as String);
    }
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Nothing useful to do; the entry goes either way.
    }
  }
}
