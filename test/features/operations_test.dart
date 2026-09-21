import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/jobs/job_controller.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/core/util/page_ranges.dart';
import 'package:pdf_toolbox/features/merge/merge_operation.dart';
import 'package:pdf_toolbox/features/split/split_operation.dart';

import '../fakes.dart';

void main() {
  late Directory root;
  late FakePdfEngine engine;
  late AppServices services;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ops_test');
    engine = FakePdfEngine();
    services = AppServices(
      engine: engine,
      store: DocumentStore(
        engine: engine,
        documentsRoot: () async => root,
        tempRoot: () async => root,
      ),
      importer: FakeFileImporter([]),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> input(String name, int pages) =>
      FakePdfEngine.writeFake(File('${root.path}/in/$name'), pages);

  List<String> library() {
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

  group('merge', () {
    test('produces one document with every input page', () async {
      final inputs = [
        await input('a.pdf', 3),
        await input('b.pdf', 4),
        await input('c.pdf', 1),
      ];
      final job = JobController<File>();
      await job.run((handle) => mergeDocuments(
            services: services,
            inputs: inputs,
            handle: handle,
            expectedPages: 8,
          ));

      expect(job.status, JobStatus.success);
      expect((await engine.inspect(job.result!)).pageCount, 8);
      expect(library(), ['a (merged).pdf']);
    });

    test('reports progress per input file', () async {
      final job = JobController<File>();
      final labels = <String>[];
      job.addListener(() {
        final label = job.progress?.label;
        if (label != null && (labels.isEmpty || labels.last != label)) {
          labels.add(label);
        }
      });

      await job.run((handle) async => mergeDocuments(
            services: services,
            inputs: [await input('a.pdf', 1), await input('b.pdf', 1)],
            handle: handle,
          ));

      expect(labels, [
        'Merging file 1 of 2...',
        'Merging file 2 of 2...',
        'Writing the merged PDF...',
      ]);
    });

    test('a failure leaves the library and the inputs untouched', () async {
      final a = await input('a.pdf', 2);
      final before = await a.readAsString();
      engine.failWith = const PdfFailure(FailureKind.corruptFile);

      final job = JobController<File>();
      await job.run((handle) async => mergeDocuments(
            services: services,
            inputs: [a, await input('b.pdf', 2)],
            handle: handle,
          ));

      expect(job.status, JobStatus.failure);
      expect(job.failure?.kind, FailureKind.corruptFile);
      expect(library(), isEmpty);
      expect(await a.readAsString(), before);
    });

    test('a wrong page count is caught before anything is saved', () async {
      final job = JobController<File>();
      await job.run((handle) async => mergeDocuments(
            services: services,
            inputs: [await input('a.pdf', 2), await input('b.pdf', 2)],
            handle: handle,
            expectedPages: 99, // deliberately wrong
          ));

      expect(job.status, JobStatus.failure);
      expect(library(), isEmpty);
    });

    test('cancelling saves nothing and cleans up the workspace', () async {
      engine.gate = Completer<void>();
      final job = JobController<File>();

      final running = job.run((handle) async => mergeDocuments(
            services: services,
            inputs: [await input('a.pdf', 1), await input('b.pdf', 1)],
            handle: handle,
          ));

      await Future<void>.delayed(Duration.zero);
      job.cancel();
      engine.gate!.complete();
      await running;

      expect(job.status, JobStatus.cancelled);
      expect(library(), isEmpty);
      expect(workspaceCount(), 0);
    });

    test('the workspace is removed after a success too', () async {
      final job = JobController<File>();
      await job.run((handle) async => mergeDocuments(
            services: services,
            inputs: [await input('a.pdf', 1), await input('b.pdf', 1)],
            handle: handle,
          ));

      expect(job.status, JobStatus.success);
      expect(workspaceCount(), 0);
    });
  });

  group('split', () {
    test('writes one file per range, named after the range', () async {
      final job = JobController<List<File>>();
      await job.run((handle) async => splitDocument(
            services: services,
            source: await input('report.pdf', 20),
            ranges: const [PageRange(1, 5), PageRange(8, 8), PageRange(11, 13)],
            handle: handle,
          ));

      expect(job.status, JobStatus.success);
      expect(job.result, hasLength(3));
      expect(library(), ['report_1-5.pdf', 'report_11-13.pdf', 'report_8.pdf']);
    });

    test('each output has exactly the pages of its range', () async {
      final job = JobController<List<File>>();
      await job.run((handle) async => splitDocument(
            services: services,
            source: await input('report.pdf', 20),
            ranges: const [PageRange(1, 5), PageRange(9, 9)],
            handle: handle,
          ));

      final counts = [
        for (final file in job.result!) (await engine.inspect(file)).pageCount,
      ];
      expect(counts, [5, 1]);
    });

    test('splitting every page produces one file per page', () async {
      final job = JobController<List<File>>();
      await job.run((handle) async => splitDocument(
            services: services,
            source: await input('short.pdf', 3),
            ranges: const [PageRange(1, 1), PageRange(2, 2), PageRange(3, 3)],
            handle: handle,
          ));

      expect(library(), ['short_1.pdf', 'short_2.pdf', 'short_3.pdf']);
    });

    test('cancelling part way keeps nothing it had already written', () async {
      engine.gate = Completer<void>();
      final job = JobController<List<File>>();

      final running = job.run((handle) async => splitDocument(
            services: services,
            source: await input('report.pdf', 10),
            ranges: const [PageRange(1, 2), PageRange(3, 4)],
            handle: handle,
          ));

      await Future<void>.delayed(Duration.zero);
      job.cancel();
      engine.gate!.complete();
      await running;

      expect(job.status, JobStatus.cancelled);
      expect(workspaceCount(), 0);
    });

    test('progress counts parts', () async {
      final job = JobController<List<File>>();
      final fractions = <double?>[];
      job.addListener(() => fractions.add(job.progress?.fraction));

      await job.run((handle) async => splitDocument(
            services: services,
            source: await input('r.pdf', 4),
            ranges: const [PageRange(1, 1), PageRange(2, 2)],
            handle: handle,
          ));

      expect(fractions, containsAllInOrder([0.0, 0.5, 1.0]));
    });
  });
}
