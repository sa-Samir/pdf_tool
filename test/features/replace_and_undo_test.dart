import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/catalog/tool_catalog.dart';
import 'package:pdf_toolbox/core/engine/compression.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/files/save_target.dart';
import 'package:pdf_toolbox/core/jobs/job_controller.dart';
import 'package:pdf_toolbox/core/pages/page_edit_session.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/compress/compress_operation.dart';
import 'package:pdf_toolbox/features/pages/page_operation.dart';
import 'package:pdf_toolbox/features/shared/undo_replace.dart';

import '../fakes.dart';

void main() {
  late Directory root;
  late FakePdfEngine engine;
  late FakeLibraryRepository library;
  late FakeEntitlements entitlements;
  late AppServices services;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('replace_undo');
    engine = FakePdfEngine();
    library = FakeLibraryRepository();
    entitlements = FakeEntitlements();
    services = AppServices(
      engine: engine,
      store: DocumentStore(
        engine: engine,
        documentsRoot: () async => root,
        tempRoot: () async => root,
      ),
      importer: FakeFileImporter([]),
      library: library,
      gallery: FakeGallerySaver(),
      entitlements: entitlements,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  List<String> namesIn(String dir) {
    final d = Directory('${root.path}/$dir');
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
  }

  List<String> savedNames() => namesIn('documents');
  List<String> revisionNames() => namesIn('revisions');

  /// A document the app owns, as one opened from the library would be.
  Future<EditableSource> owned(String name, int pages) async {
    final dir = await services.store.outputs();
    final file = await FakePdfEngine.writeFake(
      File('${dir.path}/$name'),
      pages,
      padTo: 50000,
    );
    final document = await library.record(
      file: file,
      operation: 'Merged',
      toolId: 'merge',
      pageCount: pages,
    );
    return EditableSource.owned(document, file);
  }

  /// A copy of a file picked from outside the app.
  Future<EditableSource> imported(String name, int pages) async {
    final file = await FakePdfEngine.writeFake(
      File('${root.path}/imports/$name'),
      pages,
      padTo: 50000,
    );
    return EditableSource.imported(file: file, displayName: name);
  }

  Future<SaveOutcome> edit(
    EditableSource source, {
    required int pages,
    SaveTarget? target,
    String suffix = 'edited',
  }) async {
    final job = JobController<SaveOutcome>();
    await job.run((handle) => savePageEdits(
          services: services,
          source: source,
          pages: [
            for (var i = 0; i < pages; i++) PageRef(id: i, sourceIndex: i),
          ],
          handle: handle,
          target: target ?? defaultTargetFor(source),
          suffix: suffix,
        ));
    expect(job.status, JobStatus.success, reason: '${job.failure}');
    return job.result!;
  }

  group('where a result goes when nobody is asked', () {
    test('a document the app owns is replaced', () async {
      final source = await owned('mine.pdf', 3);
      expect(source.canReplace, isTrue);
      expect(defaultTargetFor(source), SaveTarget.replaceOriginal);
    });

    test('an imported copy is not', () async {
      // The user's own file lives outside the app; writing to our copy would
      // change nothing they can see.
      final source = await imported('theirs.pdf', 3);
      expect(source.canReplace, isFalse);
      expect(defaultTargetFor(source), SaveTarget.newFile);
    });

    test('a tool that derives a new document never replaces', () async {
      final source = await owned('mine.pdf', 3);
      expect(
        defaultTargetFor(source, derivesNewDocument: true),
        SaveTarget.newFile,
        reason: 'extracting pages must not destroy what it pulled them from',
      );
    });

    test('the catalog agrees on which tools derive', () {
      bool derives(String id) =>
          ToolCatalog.all.firstWhere((t) => t.id == id).derivesNewDocument;

      for (final id in ['extract', 'split', 'merge', 'images_to_pdf']) {
        expect(derives(id), isTrue, reason: id);
      }
      for (final id in ['rotate', 'reorder', 'delete_pages', 'duplicate',
        'compress']) {
        expect(derives(id), isFalse, reason: id);
      }
    });
  });

  group('replacing', () {
    test('writes over the original and adds no second file', () async {
      final source = await owned('report.pdf', 5);
      final outcome = await edit(source, pages: 2);

      expect(savedNames(), ['report.pdf'], reason: 'no copy left behind');
      expect((await engine.inspect(source.file)).pageCount, 2);

      final entries = await library.list();
      expect(entries, hasLength(1), reason: 'updated, not duplicated');
      expect(entries.single.operation, 'Edited pages');
      expect(entries.single.pageCount, 2);
      expect(outcome.replacedExisting, isTrue);
    });

    test('keeps the previous version', () async {
      final source = await owned('report.pdf', 5);
      final before = await source.file.readAsString();

      final outcome = await edit(source, pages: 2);

      expect(revisionNames(), ['report.pdf']);
      expect(await outcome.undo!.replacement.previous.readAsString(), before);
    });

    test('an imported copy is saved alongside instead, with nothing to undo',
        () async {
      final source = await imported('theirs.pdf', 3);
      final outcome = await edit(source, pages: 1);

      expect(savedNames(), ['theirs (edited).pdf']);
      expect(source.file.existsSync(), isTrue);
      expect(outcome.undo, isNull);
      expect(revisionNames(), isEmpty);
    });

    test('saving a new file overwrites nothing, so offers no undo', () async {
      final source = await owned('report.pdf', 5);
      final outcome = await edit(source, pages: 1,
          target: SaveTarget.newFile, suffix: 'extracted');

      expect(savedNames(), ['report (extracted).pdf', 'report.pdf']);
      expect(outcome.undo, isNull);
      expect(revisionNames(), isEmpty);
    });

    test('a result with the wrong page count is refused, and keeps no '
        'revision', () async {
      final source = await owned('report.pdf', 5);
      final original = await source.file.readAsString();

      final job = JobController<Replacement>();
      await job.run((handle) async {
        final workspace = await services.store.openWorkspace();
        try {
          final temp = workspace.file('bad.pdf');
          await FakePdfEngine.writeFake(temp, 99);
          return services.store
              .replace(temp, target: source.file, expectedPages: 2);
        } finally {
          await workspace.dispose();
        }
      });

      expect(job.status, JobStatus.failure);
      expect(await source.file.readAsString(), original,
          reason: 'the original must survive a refused replace');
      expect(revisionNames(), isEmpty,
          reason: 'nothing was replaced, so nothing should be kept');
    });

    test('a failed edit leaves the original intact', () async {
      final source = await owned('report.pdf', 4);
      final original = await source.file.readAsString();
      engine.failWith = const PdfFailure(FailureKind.corruptFile);

      final job = JobController<SaveOutcome>();
      await job.run((handle) => savePageEdits(
            services: services,
            source: source,
            pages: const [PageRef(id: 0, sourceIndex: 0)],
            handle: handle,
            target: SaveTarget.replaceOriginal,
          ));

      expect(job.status, JobStatus.failure);
      expect(await source.file.readAsString(), original);
    });
  });

  group('undo', () {
    test('puts the content back and consumes the revision', () async {
      final source = await owned('report.pdf', 5);
      final before = await source.file.readAsString();
      final outcome = await edit(source, pages: 2);

      await undoReplace(services, outcome.undo!);

      expect(await source.file.readAsString(), before);
      expect((await engine.inspect(source.file)).pageCount, 5);
      expect(revisionNames(), isEmpty, reason: 'one-shot');
      expect(savedNames(), ['report.pdf'], reason: 'no stray copy');
    });

    test('restores how the library described the document', () async {
      final source = await owned('report.pdf', 5);
      final outcome = await edit(source, pages: 2);
      expect((await library.list()).single.operation, 'Edited pages');

      await undoReplace(services, outcome.undo!);

      // Restoring only the bytes would leave the library describing a version
      // that no longer exists.
      final entry = (await library.list()).single;
      expect(entry.operation, 'Merged');
      expect(entry.pageCount, 5);
      expect(await library.list(), hasLength(1));
    });
  });

  group('compress', () {
    Future<CompressionOutcome> compress(EditableSource source,
        {double ratio = 0.25}) async {
      engine.compressionRatio = ratio;
      final job = JobController<CompressionOutcome>();
      await job.run((handle) async => compressDocument(
            services: services,
            source: source,
            level: CompressionLevel.balanced,
            handle: handle,
          ));
      expect(job.status, JobStatus.success, reason: '${job.failure}');
      return job.result!;
    }

    test('replaces the document it was given', () async {
      final source = await owned('scan.pdf', 4);
      final before = await source.file.length();
      final outcome = await compress(source);

      final saved =
          await outcome.keep(services, target: defaultTargetFor(source));

      expect(savedNames(), ['scan.pdf']);
      expect(await source.file.length(), lessThan(before));
      expect((await library.list()).single.operation, contains('Compressed'));
      expect(saved.undo, isNotNull);
    });

    test('an imported copy is kept alongside', () async {
      final source = await imported('theirs.pdf', 4);
      final outcome = await compress(source);

      final saved =
          await outcome.keep(services, target: defaultTargetFor(source));

      expect(savedNames(), ['theirs (compressed).pdf']);
      expect(source.file.existsSync(), isTrue);
      expect(saved.undo, isNull);
    });

    test('undoing gives the free run back', () async {
      final source = await owned('scan.pdf', 4);
      final outcome = await compress(source);
      final saved =
          await outcome.keep(services, target: SaveTarget.replaceOriginal);
      expect(entitlements.usedFor('compress'), 1);

      await undoReplace(services, saved.undo!);

      // The user ends up with the document they started with, so charging them
      // for it would be taking a run for nothing.
      expect(entitlements.usedFor('compress'), 0);
    });

    test('a result that did not shrink was never charged, so refunds nothing',
        () async {
      final source = await owned('scan.pdf', 4);
      final outcome = await compress(source, ratio: 0.98);
      expect(outcome.result.isNoOp, isTrue);

      final saved =
          await outcome.keep(services, target: SaveTarget.replaceOriginal);
      expect(entitlements.usedFor('compress'), 0);
      expect(saved.undo!.refundToolId, isNull);

      await undoReplace(services, saved.undo!);
      expect(entitlements.usedFor('compress'), 0);
    });
  });

  group('revision retention', () {
    Future<void> revision(String name, {required Duration age}) async {
      final dir = await services.store.revisions();
      final file = File('${dir.path}/$name');
      await file.writeAsString('previous');
      await file.setLastModified(DateTime.now().subtract(age));
    }

    test('one older than the window is dropped', () async {
      await revision('stale.pdf', age: const Duration(days: 8));
      await revision('fresh.pdf', age: const Duration(hours: 1));

      await services.store.pruneRevisions();

      expect(revisionNames(), ['fresh.pdf']);
    });

    test('only the newest few survive', () async {
      for (var i = 0; i < 5; i++) {
        await revision('doc$i.pdf', age: Duration(minutes: 5 - i));
      }

      await services.store.pruneRevisions(keep: 2);

      // doc4 is the newest, doc3 next; the older three go.
      expect(revisionNames(), ['doc3.pdf', 'doc4.pdf']);
    });

    test('a revision made now survives the sweep', () async {
      final source = await owned('report.pdf', 5);
      final outcome = await edit(source, pages: 2);

      await services.store.pruneRevisions();

      expect(revisionNames(), ['report.pdf']);
      await undoReplace(services, outcome.undo!);
      expect((await engine.inspect(source.file)).pageCount, 5);
    });
  });
}
