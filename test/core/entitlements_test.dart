import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_toolbox/core/entitlements/entitlements.dart';
import 'package:pdf_toolbox/core/entitlements/sqflite_entitlements.dart';
import 'package:pdf_toolbox/core/entitlements/tool_limits.dart';
import 'package:pdf_toolbox/core/library/sqflite_library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;
  late Database db;
  late SqfliteEntitlements entitlements;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('entitlements');
    db = await SqfliteLibraryRepository.open(inMemoryDatabasePath);
    entitlements = SqfliteEntitlements(database: db);
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('allowance', () {
    test('a fresh install has the full allowance', () async {
      final allowance = await entitlements.allowanceFor('compress');
      expect(allowance.used, 0);
      expect(allowance.remaining, ToolLimits.freeTrialUses);
      expect(allowance.canUse, isTrue);
      expect(allowance.isExhausted, isFalse);
    });

    test('each use costs one, and the count persists', () async {
      await entitlements.recordUse('compress');
      expect((await entitlements.allowanceFor('compress')).remaining,
          ToolLimits.freeTrialUses - 1);

      await entitlements.recordUse('compress');
      expect((await entitlements.allowanceFor('compress')).remaining,
          ToolLimits.freeTrialUses - 2);
    });

    test('the allowance runs out and stays out', () async {
      for (var i = 0; i < ToolLimits.freeTrialUses; i++) {
        await entitlements.recordUse('compress');
      }
      var allowance = await entitlements.allowanceFor('compress');
      expect(allowance.remaining, 0);
      expect(allowance.canUse, isFalse);

      // Going past the limit must not produce a negative count.
      await entitlements.recordUse('compress');
      allowance = await entitlements.allowanceFor('compress');
      expect(allowance.remaining, 0);
      expect(allowance.isExhausted, isTrue);
    });

    test('tools have separate allowances', () async {
      await entitlements.recordUse('compress');
      await entitlements.recordUse('compress');

      expect((await entitlements.allowanceFor('compress')).remaining,
          ToolLimits.freeTrialUses - 2);
      expect((await entitlements.allowanceFor('watermark')).remaining,
          ToolLimits.freeTrialUses);
    });

    test('premium is never limited and never counted', () async {
      final premium = SqfliteEntitlements(database: db, isPremium: true);
      await premium.recordUse('compress');
      await premium.recordUse('compress');
      await premium.recordUse('compress');
      await premium.recordUse('compress');

      final allowance = await premium.allowanceFor('compress');
      expect(allowance.canUse, isTrue);
      expect(allowance.isExhausted, isFalse);
      // The free counter was not touched either.
      expect((await entitlements.allowanceFor('compress')).used, 0);
    });

    test('concurrent uses each count exactly once', () async {
      await Future.wait([
        entitlements.recordUse('compress'),
        entitlements.recordUse('compress'),
        entitlements.recordUse('compress'),
      ]);
      expect((await entitlements.allowanceFor('compress')).used, 3);
    });

    test('recording notifies listeners so counts on screen refresh', () async {
      var notified = 0;
      entitlements.changes.addListener(() => notified++);
      await entitlements.recordUse('compress');
      expect(notified, 1);
    });
  });

  group('persistence', () {
    test('counts survive closing and reopening the database', () async {
      final path = p.join(root.path, 'usage.db');
      final first = await SqfliteLibraryRepository.open(path);
      await SqfliteEntitlements(database: first).recordUse('compress');
      await first.close();

      final second = await SqfliteLibraryRepository.open(path);
      final reopened = SqfliteEntitlements(database: second);
      expect((await reopened.allowanceFor('compress')).used, 1);
      await second.close();
    });

    test('a v2 database gains the usage table without losing documents',
        () async {
      final path = p.join(root.path, 'legacy-v2.db');
      final v2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 2),
      );
      await v2.execute('''
        CREATE TABLE documents (
          id TEXT PRIMARY KEY, name TEXT NOT NULL,
          relative_path TEXT NOT NULL, size_bytes INTEGER NOT NULL,
          page_count INTEGER, operation TEXT NOT NULL, tool_id TEXT NOT NULL,
          created_at INTEGER NOT NULL, favorite INTEGER NOT NULL DEFAULT 0,
          folder_id TEXT
        )
      ''');
      await v2.execute(
        'CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, '
        'created_at INTEGER NOT NULL)',
      );
      await v2.insert('documents', {
        'id': 'keep-me',
        'name': 'old.pdf',
        'relative_path': 'old.pdf',
        'size_bytes': 10,
        'page_count': 1,
        'operation': 'Merged',
        'tool_id': 'merge',
        'created_at': 1,
        'favorite': 0,
      });
      await v2.close();

      final upgraded = await SqfliteLibraryRepository.open(path);
      expect(await upgraded.getVersion(),
          SqfliteLibraryRepository.schemaVersion);

      final rows = await upgraded.query('documents');
      expect(rows, hasLength(1), reason: 'documents survive the upgrade');

      final entitlements = SqfliteEntitlements(database: upgraded);
      await entitlements.recordUse('compress');
      expect((await entitlements.allowanceFor('compress')).used, 1);
      await upgraded.close();
    });
  });

  group('ToolAllowance arithmetic', () {
    test('remaining never goes below zero', () {
      const allowance =
          ToolAllowance(toolId: 'x', used: 99, isPremium: false);
      expect(allowance.remaining, 0);
      expect(allowance.canUse, isFalse);
    });

    test('premium always reports usable', () {
      const allowance = ToolAllowance(toolId: 'x', used: 99, isPremium: true);
      expect(allowance.canUse, isTrue);
      expect(allowance.isExhausted, isFalse);
    });
  });
}
