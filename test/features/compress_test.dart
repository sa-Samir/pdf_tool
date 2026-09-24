import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/compression.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/files/save_target.dart';
import 'package:pdf_toolbox/core/jobs/job_controller.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/compress/compress_operation.dart';

import '../fakes.dart';

void main() {
  late Directory root;
  late FakePdfEngine engine;
  late FakeLibraryRepository library;
  late FakeEntitlements entitlements;
  late AppServices services;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('compress_test');
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

  /// Padded to a realistic size so compression ratios mean something.
  Future<File> input(String name, int pages) => FakePdfEngine.writeFake(
        File('${root.path}/in/$name'),
        pages,
        padTo: 100000,
      );

  List<String> savedNames() {
    final dir = Directory('${root.path}/documents');
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
  }

  int workspaceCount() {
    final dir = Directory('${root.path}/workspaces');
    return dir.existsSync() ? dir.listSync().length : 0;
  }

  Future<CompressionOutcome> run({
    CompressionLevel level = CompressionLevel.balanced,
    String name = 'scan.pdf',
  }) async {
    final job = JobController<CompressionOutcome>();
    await job.run((handle) async => compressDocument(
          services: services,
          source: EditableSource.imported(
            file: await input(name, 6),
            displayName: name,
          ),
          level: level,
          handle: handle,
        ));
    expect(job.status, JobStatus.success, reason: '${job.failure}');
    return job.result!;
  }

  group('result reporting', () {
    test('reports the real before and after, not a promise', () async {
      engine.compressionRatio = 0.25;
      final outcome = await run();

      expect(outcome.result.originalBytes, greaterThan(0));
      expect(outcome.result.compressedBytes,
          lessThan(outcome.result.originalBytes));
      expect(outcome.result.isNoOp, isFalse);
      await outcome.discard();
    });

    test('a saving under 5% is reported as a no-op', () async {
      // The engine gave back something barely smaller.
      engine.compressionRatio = 0.97;
      final outcome = await run();

      expect(outcome.result.isNoOp, isTrue);
      await outcome.discard();
    });

    test('a result that grew is a no-op, not a negative saving', () async {
      engine.compressionRatio = 1.4;
      final outcome = await run();

      expect(outcome.result.isNoOp, isTrue);
      expect(outcome.result.savedPercent, lessThanOrEqualTo(0));
      await outcome.discard();
    });
  });

  group('keep and discard', () {
    test('nothing is saved until the user keeps it', () async {
      final outcome = await run();

      // Requirements.md 3.7: the real numbers come first, the commit after.
      expect(savedNames(), isEmpty);
      expect(await library.list(), isEmpty);

      final saved = await outcome.keep(services);
      expect(saved.file.existsSync(), isTrue);
      expect(savedNames(), ['scan (compressed).pdf']);
    });

    test('keeping records the saving in the library', () async {
      engine.compressionRatio = 0.25;
      final outcome = await run();
      await outcome.keep(services);

      final recorded = await library.list();
      expect(recorded, hasLength(1));
      expect(recorded.single.operation, contains('Compressed'));
      expect(recorded.single.operation,
          contains('${outcome.result.savedPercent}%'));
    });

    test('discarding leaves nothing behind at all', () async {
      final outcome = await run();
      await outcome.discard();

      expect(savedNames(), isEmpty);
      expect(await library.list(), isEmpty);
      expect(workspaceCount(), 0, reason: 'workspace should be gone');
    });

    test('the workspace survives until the user decides', () async {
      final outcome = await run();
      // The compressed file has to still exist for the preview and the numbers.
      expect(outcome.file.existsSync(), isTrue);
      expect(workspaceCount(), 1);
      await outcome.discard();
      expect(workspaceCount(), 0);
    });

    test('keeping also clears the workspace', () async {
      final outcome = await run();
      await outcome.keep(services);
      expect(workspaceCount(), 0);
    });

    test('settling twice is refused rather than corrupting state', () async {
      final outcome = await run();
      await outcome.keep(services);
      await expectLater(
        () => outcome.keep(services),
        throwsA(isA<StateError>()),
      );
    });

    test('discarding after keeping is harmless', () async {
      final outcome = await run();
      await outcome.keep(services);
      await outcome.discard(); // must not delete the saved file
      expect(savedNames(), ['scan (compressed).pdf']);
    });
  });

  group('failure and cancellation', () {
    test('a failure saves nothing and leaves no workspace', () async {
      engine.failWith = const PdfFailure(FailureKind.corruptFile);
      final job = JobController<CompressionOutcome>();
      await job.run((handle) async => compressDocument(
            services: services,
            source: EditableSource.imported(
              file: await input('scan.pdf', 4),
              displayName: 'scan.pdf',
            ),
            level: CompressionLevel.balanced,
            handle: handle,
          ));

      expect(job.status, JobStatus.failure);
      expect(savedNames(), isEmpty);
      expect(workspaceCount(), 0);
    });

    test('cancelling saves nothing and leaves no workspace', () async {
      engine.gate = Completer<void>();
      final job = JobController<CompressionOutcome>();
      final running = job.run((handle) async => compressDocument(
            services: services,
            source: EditableSource.imported(
              file: await input('scan.pdf', 4),
              displayName: 'scan.pdf',
            ),
            level: CompressionLevel.balanced,
            handle: handle,
          ));

      await Future<void>.delayed(Duration.zero);
      job.cancel();
      engine.gate!.complete();
      await running;

      expect(job.status, JobStatus.cancelled);
      expect(savedNames(), isEmpty);
      expect(workspaceCount(), 0);
    });

    test('the chosen level reaches the engine', () async {
      final outcome = await run(level: CompressionLevel.strong);
      expect(engine.calls, contains('compress:strong'));
      await outcome.discard();
    });
  });

  group('outlook', () {
    test('a document with no images is flagged as unlikely to shrink',
        () async {
      engine.imageCount = 0;
      final outlook =
          await services.engine.inspectForCompression(await input('t.pdf', 5));

      expect(outlook.likelyToShrink, isFalse);
      expect(outlook.pagesWithImages, 0);
    });

    test('a document with images is flagged as likely to shrink', () async {
      final outlook =
          await services.engine.inspectForCompression(await input('s.pdf', 5));

      expect(outlook.likelyToShrink, isTrue);
      expect(outlook.pagesWithImages, 5);
    });
  });

  group('the no-op rule', () {
    test('a 4% saving is a no-op and a 6% saving is not', () {
      const barely = CompressionResult(
        originalBytes: 1000,
        compressedBytes: 960,
      );
      const worthwhile = CompressionResult(
        originalBytes: 1000,
        compressedBytes: 940,
      );
      expect(barely.isNoOp, isTrue);
      expect(worthwhile.isNoOp, isFalse);
    });

    test('an empty document does not divide by zero', () {
      const empty = CompressionResult(originalBytes: 0, compressedBytes: 0);
      expect(empty.savedFraction, 0);
      expect(empty.isNoOp, isTrue);
    });
  });

  group('free runs', () {
    test('keeping a real saving spends one free run', () async {
      engine.compressionRatio = 0.25;
      final outcome = await run();
      expect(entitlements.usedFor('compress'), 0, reason: 'not spent yet');

      await outcome.keep(services);
      expect(entitlements.usedFor('compress'), 1);
    });

    test('discarding spends nothing', () async {
      engine.compressionRatio = 0.25;
      final outcome = await run();
      await outcome.discard();

      expect(entitlements.usedFor('compress'), 0);
    });

    test('keeping an already-optimized result spends nothing', () async {
      // Requirements.md 3.7: a no-op costs the user nothing, even if kept.
      engine.compressionRatio = 0.97;
      final outcome = await run();
      expect(outcome.result.isNoOp, isTrue);

      await outcome.keep(services);
      expect(entitlements.usedFor('compress'), 0);
    });

    test('a failed compression spends nothing', () async {
      engine.failWith = const PdfFailure(FailureKind.corruptFile);
      final job = JobController<CompressionOutcome>();
      await job.run((handle) async => compressDocument(
            services: services,
            source: EditableSource.imported(
              file: await input('scan.pdf', 4),
              displayName: 'scan.pdf',
            ),
            level: CompressionLevel.balanced,
            handle: handle,
          ));

      expect(job.status, JobStatus.failure);
      expect(entitlements.usedFor('compress'), 0);
    });

    test('a cancelled compression spends nothing', () async {
      engine.gate = Completer<void>();
      final job = JobController<CompressionOutcome>();
      final running = job.run((handle) async => compressDocument(
            services: services,
            source: EditableSource.imported(
              file: await input('scan.pdf', 4),
              displayName: 'scan.pdf',
            ),
            level: CompressionLevel.balanced,
            handle: handle,
          ));
      await Future<void>.delayed(Duration.zero);
      job.cancel();
      engine.gate!.complete();
      await running;

      expect(entitlements.usedFor('compress'), 0);
    });

    test('three keeps exhaust the allowance', () async {
      engine.compressionRatio = 0.25;
      for (var i = 0; i < 3; i++) {
        final outcome = await run(name: 'scan$i.pdf');
        await outcome.keep(services);
      }

      final allowance = await entitlements.allowanceFor('compress');
      expect(allowance.remaining, 0);
      expect(allowance.canUse, isFalse);
    });

    test('premium keeps do not count', () async {
      entitlements = FakeEntitlements(isPremium: true);
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
      engine.compressionRatio = 0.25;

      final outcome = await run();
      await outcome.keep(services);

      expect(entitlements.usedFor('compress'), 0);
      expect((await entitlements.allowanceFor('compress')).canUse, isTrue);
    });
  });
}
