import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/library/library_document.dart';
import 'package:pdf_toolbox/core/library/library_repository.dart';
import 'package:pdf_toolbox/core/library/sqflite_library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fakes.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;
  late DocumentStore store;
  late Database db;
  late SqfliteLibraryRepository library;

  Future<SqfliteLibraryRepository> repoWith(RetentionPolicy retention) async {
    db = await SqfliteLibraryRepository.open(inMemoryDatabasePath);
    return SqfliteLibraryRepository(
      store: store,
      database: db,
      retention: retention,
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library_test');
    final engine = FakePdfEngine();
    store = DocumentStore(
      engine: engine,
      documentsRoot: () async => root,
      tempRoot: () async => root,
    );
    library = await repoWith(RetentionPolicy.keepEverything);
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Writes a file into the outputs directory, as a finished operation would.
  Future<File> output(String name, {int pages = 1}) async {
    final dir = await store.outputs();
    return FakePdfEngine.writeFake(File(p.join(dir.path, name)), pages);
  }

  group('recording', () {
    test('a saved file becomes the newest entry', () async {
      await library.record(
        file: await output('merged.pdf'),
        operation: 'Merged',
        toolId: 'merge',
        pageCount: 7,
      );

      final recents = await library.list();
      expect(recents, hasLength(1));
      expect(recents.single.name, 'merged.pdf');
      expect(recents.single.operation, 'Merged');
      expect(recents.single.pageCount, 7);
      expect(recents.single.favorite, isFalse);
    });

    test('stores a relative path, not an absolute one', () async {
      final doc = await library.record(
        file: await output('a.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );

      // iOS changes the container path between installs; an absolute path
      // stored today would be dead tomorrow.
      expect(doc.relativePath, 'a.pdf');
      expect(doc.relativePath, isNot(contains(root.path)));
    });

    test('newest first', () async {
      for (final name in ['one.pdf', 'two.pdf', 'three.pdf']) {
        await library.record(
          file: await output(name),
          operation: 'Split',
          toolId: 'split',
        );
      }
      final names = [for (final d in await library.list()) d.name];
      expect(names, ['three.pdf', 'two.pdf', 'one.pdf']);
    });
  });

  group('lookup', () {
    setUp(() async {
      for (final name in ['alpha.pdf', 'beta.pdf', 'gamma report.pdf']) {
        await library.record(
          file: await output(name),
          operation: 'Merged',
          toolId: 'merge',
        );
      }
    });

    test('search matches part of a name, ignoring case', () async {
      final hits = await library.list(query: 'REPORT');
      expect([for (final d in hits) d.name], ['gamma report.pdf']);
    });

    test('a LIKE wildcard in the query is treated as text', () async {
      // Without escaping, "%" would match everything.
      expect(await library.list(query: '%'), isEmpty);
    });

    test('sorts by name', () async {
      final names = [
        for (final d in await library.list(sort: LibrarySort.name)) d.name,
      ];
      expect(names, ['alpha.pdf', 'beta.pdf', 'gamma report.pdf']);
    });

    test('favourites can be listed on their own', () async {
      final all = await library.list();
      await library.setFavorite(all.first.id, true);

      final favourites = await library.list(favouritesOnly: true);
      expect(favourites, hasLength(1));
      expect(favourites.single.id, all.first.id);
    });

    test('limit caps the list', () async {
      expect(await library.list(limit: 2), hasLength(2));
    });
  });

  group('rename', () {
    test('renames the entry and the file on disk', () async {
      final doc = await library.record(
        file: await output('old.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );

      final renamed = await library.rename(doc.id, 'Contract signed.pdf');
      expect(renamed.name, 'Contract signed.pdf');
      expect(await library.fileFor(renamed), isNotNull);
      expect(File(p.join((await store.outputs()).path, 'old.pdf')).existsSync(),
          isFalse);
    });

    test('adds a .pdf extension when the user leaves it off', () async {
      final doc = await library.record(
        file: await output('x.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      expect((await library.rename(doc.id, 'Invoice')).name, 'Invoice.pdf');
    });

    test('a name cannot escape the documents directory', () async {
      final doc = await library.record(
        file: await output('y.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      final renamed = await library.rename(doc.id, '../../escape.pdf');

      // Dots are fine inside a filename; what matters is that the resolved
      // file still sits inside the app's own documents directory.
      expect(renamed.name, isNot(contains(Platform.pathSeparator)));
      final outputs = await store.outputs();
      final resolved = await library.fileFor(renamed);
      expect(resolved, isNotNull);
      expect(
        p.isWithin(outputs.path, resolved!.path),
        isTrue,
        reason: '${resolved.path} escaped ${outputs.path}',
      );
    });

    test('refuses to overwrite another file', () async {
      await output('taken.pdf');
      final doc = await library.record(
        file: await output('mine.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      await expectLater(
        library.rename(doc.id, 'taken.pdf'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('delete and prune', () {
    test('delete removes the entry and the file', () async {
      final doc = await library.record(
        file: await output('gone.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      final file = await library.fileFor(doc);

      await library.delete(doc.id);
      expect(await library.list(), isEmpty);
      expect(file!.existsSync(), isFalse);
    });

    test('delete can keep the file when asked', () async {
      final doc = await library.record(
        file: await output('keep.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      final file = await library.fileFor(doc);

      await library.delete(doc.id, deleteFile: false);
      expect(await library.list(), isEmpty);
      expect(file!.existsSync(), isTrue);
    });

    test('an entry whose file vanished resolves to null and is pruned',
        () async {
      final doc = await library.record(
        file: await output('vanishing.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      await (await library.fileFor(doc))!.delete();

      expect(await library.fileFor(doc), isNull);
      expect(await library.pruneMissing(), 1);
      expect(await library.list(), isEmpty);
    });

    test('clearAll forgets everything and deletes the files', () async {
      for (final name in ['a.pdf', 'b.pdf']) {
        await library.record(
          file: await output(name),
          operation: 'Merged',
          toolId: 'merge',
        );
      }
      await library.clearAll();

      expect(await library.list(), isEmpty);
      expect((await store.outputs()).listSync(), isEmpty);
    });
  });

  group('retention', () {
    test('keeps only the most recent N', () async {
      await db.close();
      library = await repoWith(
        const RetentionPolicy(maxEntries: 3, maxAge: Duration(days: 365)),
      );
      for (var i = 0; i < 6; i++) {
        await library.record(
          file: await output('doc$i.pdf'),
          operation: 'Merged',
          toolId: 'merge',
        );
      }

      final names = [for (final d in await library.list()) d.name];
      expect(names, ['doc5.pdf', 'doc4.pdf', 'doc3.pdf']);
    });

    test('a favourite survives the cap', () async {
      await db.close();
      library = await repoWith(
        const RetentionPolicy(maxEntries: 2, maxAge: Duration(days: 365)),
      );
      final first = await library.record(
        file: await output('precious.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      await library.setFavorite(first.id, true);

      for (var i = 0; i < 5; i++) {
        await library.record(
          file: await output('filler$i.pdf'),
          operation: 'Merged',
          toolId: 'merge',
        );
      }

      final names = [for (final d in await library.list()) d.name];
      expect(names, contains('precious.pdf'));
    });
  });

  test('the schema survives a close and reopen', () async {
    final file = p.join(root.path, 'library.db');
    final first = await SqfliteLibraryRepository.open(file);
    final repo = SqfliteLibraryRepository(store: store, database: first);
    await repo.record(
      file: await output('persisted.pdf'),
      operation: 'Merged',
      toolId: 'merge',
    );
    await first.close();

    final second = await SqfliteLibraryRepository.open(file);
    final reopened = SqfliteLibraryRepository(store: store, database: second);
    expect(await reopened.list(), hasLength(1));
    expect(await second.getVersion(), SqfliteLibraryRepository.schemaVersion);
    await second.close();
  });

  group('folders', () {
    test('a new folder starts empty', () async {
      final folder = await library.createFolder('Contracts');

      expect(folder.name, 'Contracts');
      final all = await library.folders();
      expect(all, hasLength(1));
      expect(all.single.documentCount, 0);
    });

    test('a folder name must be unique and non-empty', () async {
      await library.createFolder('Taxes');
      await expectLater(
        library.createFolder('  taxes  '),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        library.createFolder('   '),
        throwsA(isA<StateError>()),
      );
    });

    test('moving a document files it, and the count follows', () async {
      final folder = await library.createFolder('Invoices');
      final doc = await library.record(
        file: await output('inv.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );

      await library.moveToFolder(doc.id, folder.id);

      expect((await library.folders()).single.documentCount, 1);
      expect(
        await library.list(scope: FolderScope.inside(folder.id)),
        hasLength(1),
      );
      expect(await library.list(scope: FolderScope.root), isEmpty);
      // Everywhere still sees it.
      expect(await library.list(), hasLength(1));
    });

    test('a document can be moved back out of a folder', () async {
      final folder = await library.createFolder('Temp');
      final doc = await library.record(
        file: await output('x.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      await library.moveToFolder(doc.id, folder.id);
      await library.moveToFolder(doc.id, null);

      expect(await library.list(scope: FolderScope.root), hasLength(1));
      expect((await library.folders()).single.documentCount, 0);
    });

    test('deleting a folder keeps its documents', () async {
      final folder = await library.createFolder('Doomed');
      final doc = await library.record(
        file: await output('keeper.pdf'),
        operation: 'Merged',
        toolId: 'merge',
      );
      await library.moveToFolder(doc.id, folder.id);

      await library.deleteFolder(folder.id);

      // Requirements.md 5.2: deleting a folder is not a way to lose files.
      expect(await library.folders(), isEmpty);
      final remaining = await library.list();
      expect(remaining, hasLength(1));
      expect(remaining.single.folderId, isNull);
      expect(await library.fileFor(remaining.single), isNotNull);
    });

    test('renaming rejects a name another folder already has', () async {
      await library.createFolder('A');
      final b = await library.createFolder('B');
      await expectLater(
        library.renameFolder(b.id, 'a'),
        throwsA(isA<StateError>()),
      );
      expect((await library.renameFolder(b.id, 'C')).name, 'C');
    });

    test('clearing the library also clears the folders', () async {
      await library.createFolder('Gone');
      await library.clearAll();
      expect(await library.folders(), isEmpty);
    });
  });

  group('schema migration', () {
    test('a v1 database gains folders without losing its documents',
        () async {
      final path = p.join(root.path, 'legacy.db');

      // Build the v1 schema by hand, as a device on the old version would have.
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 1),
      );
      await v1.execute('''
        CREATE TABLE documents (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          relative_path TEXT NOT NULL,
          size_bytes INTEGER NOT NULL,
          page_count INTEGER,
          operation TEXT NOT NULL,
          tool_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          favorite INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await v1.insert('documents', {
        'id': 'old-1',
        'name': 'legacy.pdf',
        'relative_path': 'legacy.pdf',
        'size_bytes': 1234,
        'page_count': 3,
        'operation': 'Merged',
        'tool_id': 'merge',
        'created_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        'favorite': 1,
      });
      await v1.close();

      // Reopening runs the migration.
      final upgraded = await SqfliteLibraryRepository.open(path);
      final repo = SqfliteLibraryRepository(store: store, database: upgraded);

      expect(await upgraded.getVersion(),
          SqfliteLibraryRepository.schemaVersion);

      final documents = await repo.list();
      expect(documents, hasLength(1));
      expect(documents.single.name, 'legacy.pdf');
      expect(documents.single.favorite, isTrue, reason: 'data preserved');
      expect(documents.single.folderId, isNull, reason: 'new column defaults');

      // And the new features work on the migrated database.
      final folder = await repo.createFolder('New');
      await repo.moveToFolder('old-1', folder.id);
      expect(
        await repo.list(scope: FolderScope.inside(folder.id)),
        hasLength(1),
      );
      await upgraded.close();
    });
  });
}
