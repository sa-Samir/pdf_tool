import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/compression.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/files/save_target.dart';
import 'package:pdf_toolbox/core/jobs/job_controller.dart';
import 'package:pdf_toolbox/core/library/library_document.dart';
import 'package:pdf_toolbox/core/pages/page_edit_session.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/compress/compress_operation.dart';
import 'package:pdf_toolbox/features/pages/page_operation.dart';

import '../fakes.dart';

void main() {
  late Directory root;
  late FakePdfEngine engine;
  late FakeLibraryRepository library;
  late AppServices services;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('save_target');
    engine = FakePdfEngine();
    library = FakeLibraryRepository();
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
      entitlements: FakeEntitlements(),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  List<String> savedNames() {
    final dir = Directory('${root.path}/documents');
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
  }

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

  group('what can be replaced', () {
    test('a library document can be replaced', () async {
      expect((await owned('mine.pdf', 3)).canReplace, isTrue);
    });

    test('an imported copy cannot', () async {
      // The user's own file lives outside the app; writing to our copy would
      // change nothing they can see.
      expect((await imported('theirs.pdf', 3)).canReplace, isFalse);
    });
  });

  group('page edits', () {
    test('saving as a new file leaves the original alone', () async {
      final source = await owned('report.pdf', 5);
      final before = await source.file.length();

      final job = JobController<File>();
      await job.run((handle) => savePageEdits(
            services: services,
            source: source,
            pages: const [PageRef(id: 0, sourceIndex: 0)],
            handle: handle,
          ));

      expect(job.status, JobStatus.success, reason: '${job.failure}');
      expect(source.file.existsSync(), isTrue);
      expect(await source.file.length(), before, reason: 'untouched');
      expect(savedNames(), ['report (edited).pdf', 'report.pdf']);
      expect(await library.list(), hasLength(2));
    });

    test('replacing writes over the original and adds no second file',
        () async {
      final source = await owned('report.pdf', 5);

      final job = JobController<File>();
      await job.run((handle) => savePageEdits(
            services: services,
            source: source,
            pages: const [
              PageRef(id: 0, sourceIndex: 0),
              PageRef(id: 1, sourceIndex: 1),
            ],
            handle: handle,
            target: SaveTarget.replaceOriginal,
          ));

      expect(job.status, JobStatus.success, reason: '${job.failure}');
      expect(savedNames(), ['report.pdf'], reason: 'no copy left behind');
      expect((await engine.inspect(source.file)).pageCount, 2);

      // One library entry, updated rather than duplicated.
      final entries = await library.list();
      expect(entries, hasLength(1));
      expect(entries.single.operation, 'Edited pages');
      expect(entries.single.pageCount, 2);
    });

    test('a replace that produces the wrong page count is refused',
        () async {
      final source = await owned('report.pdf', 5);
      final original = await source.file.readAsString();

      // The fake writes one page per entry, so claiming otherwise fails
      // verification before anything is swapped.
      final job = JobController<File>();
      await job.run((handle) async {
        final workspace = await services.store.openWorkspace();
        try {
          final temp = workspace.file('bad.pdf');
          await FakePdfEngine.writeFake(temp, 99);
          return services.store.replace(
            temp,
            target: source.file,
            expectedPages: 2,
          );
        } finally {
          await workspace.dispose();
        }
      });

      expect(job.status, JobStatus.failure);
      expect(await source.file.readAsString(), original,
          reason: 'the original must survive a refused replace');
    });

    test('a failed edit leaves the original intact', () async {
      final source = await owned('report.pdf', 4);
      final original = await source.file.readAsString();
      engine.failWith = const PdfFailure(FailureKind.corruptFile);

      final job = JobController<File>();
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

    test('replace falls back to a new file when nothing can be replaced',
        () async {
      final source = await imported('theirs.pdf', 3);

      final job = JobController<File>();
      await job.run((handle) => savePageEdits(
            services: services,
            source: source,
            pages: const [PageRef(id: 0, sourceIndex: 0)],
            handle: handle,
            // Even asked to replace, an imported copy must not be treated as
            // the user's file.
            target: SaveTarget.replaceOriginal,
          ));

      expect(job.status, JobStatus.success, reason: '${job.failure}');
      expect(savedNames(), ['theirs (edited).pdf']);
      expect(source.file.existsSync(), isTrue);
    });
  });

  group('compress', () {
    Future<CompressionOutcome> compress(EditableSource source) async {
      engine.compressionRatio = 0.25;
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

    test('keeping as a new file leaves the original', () async {
      final source = await owned('scan.pdf', 4);
      final outcome = await compress(source);
      await outcome.keep(services);

      expect(savedNames(), ['scan (compressed).pdf', 'scan.pdf']);
      expect(await library.list(), hasLength(2));
    });

    test('replacing swaps the file and updates the one entry', () async {
      final source = await owned('scan.pdf', 4);
      final before = await source.file.length();
      final outcome = await compress(source);

      await outcome.keep(services, target: SaveTarget.replaceOriginal);

      expect(savedNames(), ['scan.pdf']);
      expect(await source.file.length(), lessThan(before));

      final entries = await library.list();
      expect(entries, hasLength(1));
      expect(entries.single.operation, contains('Compressed'));
    });

    test('an imported copy is never replaced', () async {
      final source = await imported('theirs.pdf', 4);
      final outcome = await compress(source);

      await outcome.keep(services, target: SaveTarget.replaceOriginal);

      expect(savedNames(), ['theirs (compressed).pdf']);
      expect(source.file.existsSync(), isTrue);
    });
  });
}
