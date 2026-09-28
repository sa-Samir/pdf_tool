import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/entitlements/tool_limits.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/files/file_importer.dart';
import 'package:pdf_toolbox/core/images/page_layout.dart';
import 'package:pdf_toolbox/core/jobs/job_controller.dart';
import 'package:pdf_toolbox/core/scan/document_scanner.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/images_to_pdf/images_to_pdf_operation.dart';
import 'package:pdf_toolbox/features/images_to_pdf/images_to_pdf_page.dart';
import 'package:pdf_toolbox/features/scan/scan_flow.dart';

import '../fakes.dart';

/// The document scanner (requirements.md 3.10).
///
/// The platform scanners do the capture; what is tested here is everything
/// around them -- availability, the page cap, the wording, and the fact that a
/// scan becomes an ordinary set of images the moment it comes back.
void main() {
  group('wrapping captured pages', () {
    test('a page keeps its name and the size the platform reported', () {
      final result = FakeDocumentScanner.captured(
        ['page-001.jpg', 'page-002.jpg'],
        bytesEach: 240000,
      );

      final images = pickedFromScan(result);

      expect(images, hasLength(2));
      expect(images.first.name, 'page-001.jpg');
      expect(images.first.document.sizeBytes, 240000);
      // Nothing above touched the filesystem, which is what lets the review
      // screen be driven in a widget test at all.
    });

    test('a cancelled scan has nothing to wrap', () {
      expect(pickedFromScan(const ScanResult.cancelled()), isEmpty);
    });
  });

  group('what the user is told', () {
    test('backing out of the camera is not announced', () {
      expect(describeScan(const ScanResult.cancelled()), isNull);
    });

    test('a successful capture is not announced either', () {
      // The review screen appearing is the feedback.
      expect(describeScan(FakeDocumentScanner.captured(['a.jpg'])), isNull);
    });

    test('a device that cannot scan says so', () {
      expect(
        describeScan(const ScanResult(ScanOutcome.unavailable)),
        'Scanning is not available on this device.',
      );
    });

    test('a scanner that failed to open says so', () {
      expect(
        describeScan(const ScanResult(ScanOutcome.failed)),
        'The scanner could not be opened.',
      );
    });

    test('a capture that produced nothing is not silently ignored', () {
      expect(
        describeScan(const ScanResult(ScanOutcome.captured)),
        'The scanner returned no pages.',
      );
    });
  });

  group('the free-tier page cap', () {
    late AppServices services;

    setUp(() {
      final engine = MemoryFakeEngine(const {});
      services = AppServices(
        engine: engine,
        store: DocumentStore(engine: engine),
        importer: FakeFileImporter([]),
        library: FakeLibraryRepository(),
        gallery: FakeGallerySaver(),
        entitlements: FakeEntitlements(),
        scanner: FakeDocumentScanner(),
      );
    });

    List<PickedImage> pages(int n) => pickedFromScan(
          FakeDocumentScanner.captured([for (var i = 0; i < n; i++) 'p$i.jpg']),
        );

    test('does not apply while the free tier is switched off', () {
      final capped = capScan(services, captured: pages(9));

      expect(capped.accepted, hasLength(9));
      expect(capped.capped, isFalse);
    });

    group('with the free tier switched on', () {
      enforceFreeTier();

      test('trims a capture to the advertised number', () {
        final capped = capScan(services, captured: pages(9));

        expect(capped.accepted, hasLength(ToolLimits.scannerFreePages));
        expect(capped.capped, isTrue,
            reason: 'the user has to be told, not silently given fewer');
      });

      test('counts pages already held', () {
        final capped = capScan(
          services,
          captured: pages(3),
          existing: ToolLimits.scannerFreePages - 1,
        );

        expect(capped.accepted, hasLength(1));
        expect(capped.capped, isTrue);
      });

      test('a capture that fits is not reported as capped', () {
        final capped = capScan(services, captured: pages(1));

        expect(capped.accepted, hasLength(1));
        expect(capped.capped, isFalse);
      });
    });
  });

  group('the review screen', () {
    late FakeDocumentScanner scanner;

    Widget host(List<PickedImage> initial) {
      final engine = MemoryFakeEngine(const {});
      scanner = FakeDocumentScanner();
      return AppServicesScope(
        services: AppServices(
          engine: engine,
          store: DocumentStore(engine: engine),
          importer: FakeFileImporter([]),
          library: FakeLibraryRepository(),
          gallery: FakeGallerySaver(),
          entitlements: FakeEntitlements(),
          scanner: scanner,
        ),
        child: MaterialApp(
          home: ImagesToPdfPage(
            source: ImageSource.scanned,
            initial: initial,
          ),
        ),
      );
    }

    Future<void> pump(WidgetTester tester, {int pages = 0}) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(pickedFromScan(
        FakeDocumentScanner.captured([for (var i = 0; i < pages; i++) 'p$i.jpg']),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('speaks about paper, not photos', (tester) async {
      await pump(tester);

      expect(find.text('Scan document'), findsWidgets);
      expect(find.text('Scan paper with the camera'), findsOneWidget);
      expect(find.text('Open the scanner'), findsOneWidget);
      // The photo wording would be wrong here.
      expect(find.text('Choose images'), findsNothing);
      expect(find.text('Turn photos into a PDF'), findsNothing);
    });

    testWidgets('captured pages arrive ready to save', (tester) async {
      await pump(tester, pages: 3);

      expect(find.text('Create 3 pages'), findsOneWidget);
      expect(find.text('Scan more'), findsOneWidget);
      expect(find.text('Add more'), findsNothing);
    });

    testWidgets('adding more opens the camera, not the photo picker',
        (tester) async {
      await pump(tester, pages: 1);

      await tester.tap(find.text('Scan more'));
      await tester.pumpAndSettle();

      expect(scanner.calls, hasLength(1));
    });
  });

  group('saving a scan', () {
    late Directory root;
    late FakePdfEngine engine;
    late FakeLibraryRepository library;
    late AppServices services;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('scan_save');
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
        images: FakeImageNormalizer(),
        scanner: FakeDocumentScanner(),
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<PickedImage> page(String name) async {
      final file = File('${root.path}/scans/$name');
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

    test('is recorded as a scan, not as images', () async {
      final images = [await page('page-001.jpg'), await page('page-002.jpg')];

      final job = JobController<File>();
      await job.run((handle) => imagesToPdfDocument(
            services: services,
            images: images,
            options: const ImagePageOptions(),
            handle: handle,
            source: ImageSource.scanned,
          ));

      expect(job.status, JobStatus.success, reason: '${job.failure}');
      final entry = (await library.list()).single;
      expect(entry.operation, 'Scanned 2 pages');
      expect(entry.toolId, 'scan');
      expect(entry.pageCount, 2);
      expect(entry.name, 'Scan.pdf',
          reason: 'the scanner page file names mean nothing to anyone');
    });

    test('picking photos is still recorded as images', () async {
      final images = [await page('holiday.jpg')];

      final job = JobController<File>();
      await job.run((handle) => imagesToPdfDocument(
            services: services,
            images: images,
            options: const ImagePageOptions(),
            handle: handle,
          ));

      expect(job.status, JobStatus.success, reason: '${job.failure}');
      final entry = (await library.list()).single;
      expect(entry.operation, 'From 1 image');
      expect(entry.toolId, 'images_to_pdf');
      expect(entry.name, 'holiday.pdf');
    });
  });
}
