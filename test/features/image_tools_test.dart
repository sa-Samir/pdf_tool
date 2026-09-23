import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/files/file_importer.dart';
import 'package:pdf_toolbox/core/images/image_normalizer.dart';
import 'package:pdf_toolbox/core/images/page_layout.dart';
import 'package:pdf_toolbox/core/jobs/job_controller.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/images_to_pdf/images_to_pdf_operation.dart';
import 'package:pdf_toolbox/features/pdf_to_images/pdf_to_images_operation.dart';

import '../fakes.dart';

void main() {
  late Directory root;
  late FakePdfEngine engine;
  late FakeImageNormalizer normalizer;
  late FakeLibraryRepository library;
  late AppServices services;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('image_tools');
    engine = FakePdfEngine();
    normalizer = FakeImageNormalizer();
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
      images: normalizer,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<PickedImage> picked(String name) async {
    final file = File('${root.path}/in/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(kTinyPng);
    return PickedImage(
      document: ImportedDocument(
        file: file,
        displayName: name,
        sizeBytes: kTinyPng.length,
      ),
    );
  }

  Future<File> sourcePdf(String name, int pages) =>
      FakePdfEngine.writeFake(File('${root.path}/in/$name'), pages);

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

  group('images to PDF', () {
    test('one page per image, saved and recorded', () async {
      final job = JobController<File>();
      await job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [
              await picked('a.jpg'),
              await picked('b.jpg'),
              await picked('c.jpg'),
            ],
            options: const ImagePageOptions(),
            handle: handle,
          ));

      expect(job.status, JobStatus.success, reason: '${job.failure}');
      expect((await engine.inspect(job.result!)).pageCount, 3);
      expect(savedNames(), ['Images.pdf']);

      final recorded = await library.list();
      expect(recorded.single.operation, 'From 3 images');
      expect(recorded.single.pageCount, 3);
    });

    test('a single image keeps its own name', () async {
      final job = JobController<File>();
      await job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [await picked('holiday.jpg')],
            options: const ImagePageOptions(),
            handle: handle,
          ));

      expect(savedNames(), ['holiday.pdf']);
    });

    test('images are normalised one at a time, never all at once', () async {
      final job = JobController<File>();
      await job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [
              await picked('a.jpg'),
              await picked('b.jpg'),
            ],
            options: const ImagePageOptions(),
            handle: handle,
          ));

      // One normalize call per image, in order.
      expect(normalizer.calls, hasLength(2));
      expect(normalizer.calls.first, contains('a.jpg'));
      expect(normalizer.calls.last, contains('b.jpg'));
    });

    test('the chosen quality reaches the normalizer', () async {
      final job = JobController<File>();
      await job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [await picked('a.jpg')],
            options: const ImagePageOptions(quality: ImageQuality.low),
            handle: handle,
          ));

      expect(normalizer.calls.single, contains('q62'));
    });

    test('a rotation is applied when the image is prepared', () async {
      final image = (await picked('a.jpg')).rotated(1);
      final job = JobController<File>();
      await job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [image],
            options: const ImagePageOptions(),
            handle: handle,
          ));

      expect(normalizer.calls.single, contains('r1'));
    });

    test('reports progress per image', () async {
      final labels = <String>[];
      final job = JobController<File>();
      job.addListener(() {
        final label = job.progress?.label;
        if (label != null && (labels.isEmpty || labels.last != label)) {
          labels.add(label);
        }
      });
      await job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [await picked('a.jpg'), await picked('b.jpg')],
            options: const ImagePageOptions(),
            handle: handle,
          ));

      expect(labels, [
        'Preparing image 1 of 2...',
        'Preparing image 2 of 2...',
        'Building the PDF...',
        'Done',
      ]);
    });

    test('a failure saves nothing and leaves no workspace', () async {
      engine.failWith = const PdfFailure(FailureKind.corruptFile);
      final job = JobController<File>();
      await job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [await picked('a.jpg')],
            options: const ImagePageOptions(),
            handle: handle,
          ));

      expect(job.status, JobStatus.failure);
      expect(savedNames(), isEmpty);
      expect(workspaceCount(), 0);
      expect(await library.list(), isEmpty);
    });

    test('cancelling saves nothing', () async {
      engine.gate = Completer<void>();
      final job = JobController<File>();
      final running = job.run((handle) async => imagesToPdfDocument(
            services: services,
            images: [await picked('a.jpg')],
            options: const ImagePageOptions(),
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
  });

  group('PDF to images', () {
    test('writes one file per page, named by page number', () async {
      final job = JobController<List<File>>();
      await job.run((handle) async => exportPagesAsImages(
            services: services,
            source: await sourcePdf('report.pdf', 3),
            pageIndices: const [0, 1, 2],
            dpi: ExportDpi.good,
            format: ImageFormat.png,
            handle: handle,
          ));

      expect(job.status, JobStatus.success, reason: '${job.failure}');
      final names = [
        for (final f in job.result!) f.path.split(Platform.pathSeparator).last,
      ];
      expect(names, ['report_001.png', 'report_002.png', 'report_003.png']);
    });

    test('exports only the pages asked for', () async {
      final job = JobController<List<File>>();
      await job.run((handle) async => exportPagesAsImages(
            services: services,
            source: await sourcePdf('r.pdf', 10),
            pageIndices: const [1, 4],
            dpi: ExportDpi.good,
            format: ImageFormat.png,
            handle: handle,
          ));

      final names = [
        for (final f in job.result!) f.path.split(Platform.pathSeparator).last,
      ];
      expect(names, ['r_002.png', 'r_005.png']);
    });

    test('JPG goes through the encoder, PNG does not', () async {
      final job = JobController<List<File>>();
      await job.run((handle) async => exportPagesAsImages(
            services: services,
            source: await sourcePdf('j.pdf', 2),
            pageIndices: const [0, 1],
            dpi: ExportDpi.good,
            format: ImageFormat.jpg,
            handle: handle,
          ));

      expect(normalizer.calls.where((c) => c.startsWith('toJpeg')), hasLength(2));
      expect(job.result!.first.path, endsWith('.jpg'));
    });

    test('a higher DPI asks the engine for more pixels', () async {
      final job = JobController<List<File>>();
      await job.run((handle) async => exportPagesAsImages(
            services: services,
            source: await sourcePdf('d.pdf', 1),
            pageIndices: const [0],
            dpi: ExportDpi.print,
            format: ImageFormat.png,
            handle: handle,
          ));

      // A4 at 300 dpi is about 2480 x 3508.
      expect(
        engine.calls.where((c) => c.startsWith('renderPageAt')),
        contains(contains('2480x3508')),
      );
    });

    test('cancelling deletes everything it had already written', () async {
      engine.gate = Completer<void>();
      final job = JobController<List<File>>();
      final running = job.run((handle) async => exportPagesAsImages(
            services: services,
            source: await sourcePdf('c.pdf', 5),
            pageIndices: const [0, 1, 2, 3, 4],
            dpi: ExportDpi.good,
            format: ImageFormat.png,
            handle: handle,
          ));

      await Future<void>.delayed(Duration.zero);
      job.cancel();
      engine.gate!.complete();
      await running;

      expect(job.status, JobStatus.cancelled);
      final exports = Directory('${root.path}/exports');
      final leftovers = exports.existsSync()
          ? exports.listSync(recursive: true).whereType<File>().length
          : 0;
      expect(leftovers, 0, reason: 'a cancelled export must leave nothing');
    });

    test('a failure part way leaves nothing behind', () async {
      engine.failWith = const PdfFailure(FailureKind.corruptFile);
      final job = JobController<List<File>>();
      await job.run((handle) async => exportPagesAsImages(
            services: services,
            source: await sourcePdf('f.pdf', 3),
            pageIndices: const [0, 1, 2],
            dpi: ExportDpi.good,
            format: ImageFormat.png,
            handle: handle,
          ));

      expect(job.status, JobStatus.failure);
      final exports = Directory('${root.path}/exports');
      final leftovers = exports.existsSync()
          ? exports.listSync(recursive: true).whereType<File>().length
          : 0;
      expect(leftovers, 0);
    });
  });

  group('export estimate', () {
    test('is measured from a real page, and scales with page count', () async {
      final source = await sourcePdf('e.pdf', 8);
      final one = await estimateExport(
        services: services,
        source: source,
        pageIndices: const [0],
        dpi: ExportDpi.good,
        format: ImageFormat.png,
      );
      final all = await estimateExport(
        services: services,
        source: source,
        pageIndices: const [0, 1, 2, 3, 4, 5, 6, 7],
        dpi: ExportDpi.good,
        format: ImageFormat.png,
      );

      expect(one.pageCount, 1);
      expect(all.pageCount, 8);
      expect(all.totalBytes, one.totalBytes * 8);
    });

    test('reports the pixel size for the chosen DPI', () async {
      final estimate = await estimateExport(
        services: services,
        source: await sourcePdf('px.pdf', 1),
        pageIndices: const [0],
        dpi: ExportDpi.screen,
        format: ImageFormat.png,
      );

      // A4 at 72 dpi is about 595 x 842.
      expect(estimate.pixelWidth, closeTo(595, 2));
      expect(estimate.pixelHeight, closeTo(842, 2));
    });

    test('JPG is estimated smaller than PNG', () async {
      final source = await sourcePdf('cmp.pdf', 4);
      final png = await estimateExport(
        services: services, source: source, pageIndices: const [0, 1, 2, 3],
        dpi: ExportDpi.good, format: ImageFormat.png,
      );
      final jpg = await estimateExport(
        services: services, source: source, pageIndices: const [0, 1, 2, 3],
        dpi: ExportDpi.good, format: ImageFormat.jpg,
      );

      expect(jpg.totalBytes, lessThan(png.totalBytes));
    });
  });
}
