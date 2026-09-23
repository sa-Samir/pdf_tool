import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/pdf_engine.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/viewer/viewer_controller.dart';
import 'package:pdf_toolbox/features/viewer/viewer_page.dart';
import 'package:pdf_toolbox/features/viewer/widgets/viewer_page_view.dart';

import '../fakes.dart';

void main() {
  late MemoryFakeEngine engine;
  late AppServices services;
  final file = File('/memory/lease.pdf');

  AppServices build({int pages = 6}) {
    engine = MemoryFakeEngine({'/memory/lease.pdf': pages});
    return AppServices(
      engine: engine,
      store: DocumentStore(engine: engine),
      importer: FakeFileImporter([]),
      library: FakeLibraryRepository(),
      gallery: FakeGallerySaver(),
      images: FakeImageNormalizer(),
    );
  }

  setUp(() => services = build());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppServicesScope(
      services: services,
      child: MaterialApp(home: PdfViewerPage(file: file, title: 'lease.pdf')),
    ));
    await tester.pumpAndSettle();
  }

  group('controller', () {
    test('opens and reports the page geometry', () async {
      final controller = ViewerController(engine: engine, file: file);
      await controller.open();

      expect(controller.status, ViewerStatus.ready);
      expect(controller.pageCount, 6);
      expect(controller.pages, isNotNull);
      controller.dispose();
    });

    test('an encrypted document asks for a password', () async {
      engine.requiredPassword = 'hunter2';
      final controller = ViewerController(engine: engine, file: file);
      await controller.open();

      expect(controller.status, ViewerStatus.needsPassword);
      controller.dispose();
    });

    test('a wrong password is reported as wrong, not as damage', () async {
      engine.requiredPassword = 'hunter2';
      final controller = ViewerController(engine: engine, file: file);
      await controller.open(password: 'nope');

      expect(controller.status, ViewerStatus.wrongPassword);
      controller.dispose();
    });

    test('the right password opens the document', () async {
      engine.requiredPassword = 'hunter2';
      final controller = ViewerController(engine: engine, file: file);
      await controller.open(password: 'hunter2');

      expect(controller.status, ViewerStatus.ready);
      controller.dispose();
    });

    test('search collects hits and starts at the first', () async {
      engine.searchHits['rent'] = const [
        TextHit(pageIndex: 0, text: 'rent', x: 10, y: 20, width: 30, height: 12),
        TextHit(pageIndex: 3, text: 'rent', x: 40, y: 60, width: 30, height: 12),
      ];
      final controller = ViewerController(engine: engine, file: file);
      await controller.open();
      await controller.search('rent');

      expect(controller.hits, hasLength(2));
      expect(controller.currentHit, 0);
      expect(controller.hitsOn(3), hasLength(1));
      expect(controller.hitsOn(1), isEmpty);
      controller.dispose();
    });

    test('stepping through hits wraps around', () async {
      engine.searchHits['a'] = const [
        TextHit(pageIndex: 0, text: 'a', x: 0, y: 0, width: 1, height: 1),
        TextHit(pageIndex: 2, text: 'a', x: 0, y: 0, width: 1, height: 1),
      ];
      final controller = ViewerController(engine: engine, file: file);
      await controller.open();
      await controller.search('a');

      expect(controller.nextHit(), 2);
      expect(controller.nextHit(), 0);
      expect(controller.previousHit(), 2);
      controller.dispose();
    });

    test('a search with no matches leaves nothing selected', () async {
      final controller = ViewerController(engine: engine, file: file);
      await controller.open();
      await controller.search('nothing here');

      expect(controller.hits, isEmpty);
      expect(controller.currentHit, -1);
      expect(controller.nextHit(), isNull);
      controller.dispose();
    });

    test('clearing the search drops the hits', () async {
      engine.searchHits['x'] = const [
        TextHit(pageIndex: 0, text: 'x', x: 0, y: 0, width: 1, height: 1),
      ];
      final controller = ViewerController(engine: engine, file: file);
      await controller.open();
      await controller.search('x');
      expect(controller.hits, hasLength(1));

      controller.clearSearch();
      expect(controller.hits, isEmpty);
      expect(controller.hasSearch, isFalse);
      controller.dispose();
    });
  });

  group('screen', () {
    testWidgets('shows a page per page of the document', (tester) async {
      await pump(tester);
      expect(find.byType(ViewerPageView), findsWidgets);
      expect(find.textContaining('of 6'), findsOneWidget);
    });

    testWidgets('asks for a password, saying it is never saved',
        (tester) async {
      services = build();
      engine.requiredPassword = 'hunter2';
      await pump(tester);

      expect(find.text('This PDF is password-protected.'), findsOneWidget);
      expect(find.textContaining('never'), findsOneWidget);
      expect(find.byType(ViewerPageView), findsNothing);
    });

    testWidgets('a wrong password says so and lets the user retry',
        (tester) async {
      services = build();
      engine.requiredPassword = 'hunter2';
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      expect(find.text("That password didn't work."), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      expect(find.byType(ViewerPageView), findsWidgets);
    });

    testWidgets('search reports the match count and moves between hits',
        (tester) async {
      services = build();
      engine.searchHits['rent'] = const [
        TextHit(pageIndex: 0, text: 'rent', x: 10, y: 20, width: 30, height: 12),
        TextHit(pageIndex: 2, text: 'rent', x: 10, y: 20, width: 30, height: 12),
      ];
      await pump(tester);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'rent');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('1 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
    });

    testWidgets('a search with no matches says so', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('a document that cannot be opened explains itself',
        (tester) async {
      services = build(pages: 0);
      engine = MemoryFakeEngine(const {});
      services = AppServices(
        engine: engine,
        store: DocumentStore(engine: engine),
        importer: FakeFileImporter([]),
        library: FakeLibraryRepository(),
      gallery: FakeGallerySaver(),
        images: FakeImageNormalizer(),
      );
      await pump(tester);

      // An unknown file has no geometry; the viewer must not pretend.
      expect(find.byType(ViewerPageView), findsNothing);
    });

    testWidgets('offers Go to page', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Go to page'));
      await tester.pumpAndSettle();
      expect(find.text('Page number'), findsOneWidget);
      expect(find.textContaining('1 to 6'), findsOneWidget);
    });
  });

  test('a failure other than a password is surfaced as a failure', () async {
    final failing = FakePdfEngine()
      ..failInspectWith = const PdfFailure(FailureKind.corruptFile);
    final controller = ViewerController(
      engine: failing,
      file: File('/nope.pdf'),
    );
    await controller.open();
    expect(controller.status, ViewerStatus.failed);
    controller.dispose();
  });
}
