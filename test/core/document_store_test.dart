import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';

import '../fakes.dart';

void main() {
  late Directory root;
  late FakePdfEngine engine;
  late DocumentStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('store_test');
    engine = FakePdfEngine();
    store = DocumentStore(
      engine: engine,
      documentsRoot: () async => root,
      tempRoot: () async => root,
    );
  });

  /// The library's contents, tolerating the directory never having been
  /// created -- which is itself the correct outcome when nothing committed.
  List<String> savedNames() {
    final dir = Directory('${root.path}/documents');
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
  }

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('workspaces', () {
    test('are removed on dispose', () async {
      final workspace = await store.openWorkspace();
      await FakePdfEngine.writeFake(workspace.file('scratch.pdf'), 1);
      expect(workspace.directory.existsSync(), isTrue);

      await workspace.dispose();
      expect(workspace.directory.existsSync(), isFalse);
    });

    test('sweeping removes ones a crash left behind', () async {
      final abandoned = await store.openWorkspace();
      await FakePdfEngine.writeFake(abandoned.file('half-written.pdf'), 1);

      await store.sweepWorkspaces();
      expect(abandoned.directory.existsSync(), isFalse);
    });

    test('two workspaces never collide', () async {
      final a = await store.openWorkspace();
      final b = await store.openWorkspace();
      expect(a.directory.path, isNot(b.directory.path));
    });
  });

  group('commit', () {
    test('verifies the output before it reaches the library', () async {
      final workspace = await store.openWorkspace();
      final temp = await FakePdfEngine.writeFake(workspace.file('t.pdf'), 9);

      final saved = await store.commit(temp, desiredName: 'out.pdf');
      expect(await saved.exists(), isTrue);
      expect(saved.path, contains('documents'));
      // The temp file was moved, not copied.
      expect(await temp.exists(), isFalse);
    });

    test('rejects an output with the wrong page count, and deletes it',
        () async {
      final workspace = await store.openWorkspace();
      final temp = await FakePdfEngine.writeFake(workspace.file('t.pdf'), 3);

      await expectLater(
        store.commit(temp, desiredName: 'out.pdf', expectedPages: 5),
        throwsA(isA<PdfFailure>()
            .having((f) => f.kind, 'kind', FailureKind.unknown)),
      );
      expect(await temp.exists(), isFalse);
      expect(savedNames(), isEmpty);
    });

    test('rejects an unreadable output rather than saving it', () async {
      final workspace = await store.openWorkspace();
      final temp = workspace.file('t.pdf');
      await temp.writeAsString('not a pdf at all');

      await expectLater(
        store.commit(temp, desiredName: 'out.pdf'),
        throwsA(isA<PdfFailure>()),
      );
      expect(savedNames(), isEmpty);
    });

    test('never overwrites an existing file', () async {
      for (var i = 0; i < 3; i++) {
        final workspace = await store.openWorkspace();
        final temp = await FakePdfEngine.writeFake(workspace.file('t.pdf'), 1);
        await store.commit(temp, desiredName: 'report.pdf');
      }

      expect(savedNames(), ['report (2).pdf', 'report (3).pdf', 'report.pdf']);
    });
  });

  group('sanitizeFileName', () {
    test('strips path separators so a name cannot escape its directory', () {
      expect(sanitizeFileName('../../etc/passwd.pdf'), '.._.._etc_passwd.pdf');
      expect(sanitizeFileName(r'a\b.pdf'), 'a_b.pdf');
    });

    test('replaces characters the platforms reject', () {
      expect(sanitizeFileName('in:voice?*.pdf'), 'in_voice__.pdf');
    });

    test('falls back rather than producing an empty name', () {
      expect(sanitizeFileName(''), 'document');
      expect(sanitizeFileName('   '), 'document');
      expect(sanitizeFileName('..'), 'document');
    });

    test('truncates a very long name but keeps the extension', () {
      final result = sanitizeFileName('${'x' * 500}.pdf');
      expect(result.endsWith('.pdf'), isTrue);
      expect(result.length, lessThan(256));
    });
  });

  test('imports are copied into the sandbox, leaving the source alone',
      () async {
    final outside = await FakePdfEngine.writeFake(
      File('${root.path}/picked.pdf'),
      4,
    );

    final adopted = await store.adoptImport(outside, 'picked.pdf');
    expect(adopted.path, contains('imports'));
    expect(await outside.exists(), isTrue);
    expect(await adopted.readAsString(), await outside.readAsString());
  });
}
