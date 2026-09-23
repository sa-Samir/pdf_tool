import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/compression.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/compress/compress_page.dart';

import '../fakes.dart';

/// The copy on this screen is the feature (requirements.md 3.7), so it is
/// tested as carefully as the arithmetic.
void main() {
  late FakeFileImporter importer;
  late MemoryFakeEngine engine;
  late AppServices services;

  AppServices build() {
    engine = MemoryFakeEngine({'/memory/doc.pdf': 12});
    return AppServices(
      engine: engine,
      store: DocumentStore(engine: engine),
      importer: importer,
      library: FakeLibraryRepository(),
      gallery: FakeGallerySaver(),
    );
  }

  setUp(() {
    importer = FakeFileImporter([]);
    services = build();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppServicesScope(
      services: services,
      child: const MaterialApp(home: CompressPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    importer.queued.add([memoryDocument('doc.pdf')]);
    await pump(tester);
    await tester.tap(find.text('Choose a PDF'));
    await tester.pumpAndSettle();
  }

  testWidgets('promises nothing before a file is chosen', (tester) async {
    await pump(tester);
    expect(find.text('Make a large PDF smaller'), findsOneWidget);
    expect(find.textContaining('real numbers'), findsOneWidget);
  });

  testWidgets('an image-heavy document is described as likely to shrink',
      (tester) async {
    await choose(tester);

    expect(find.text('This should get a lot smaller'), findsOneWidget);
    expect(find.textContaining('12 of 12 pages'), findsOneWidget);
    // Measured, from docs/benchmarks.md.
    expect(find.textContaining('76%'), findsOneWidget);
  });

  testWidgets('a text document is told plainly that it will not shrink',
      (tester) async {
    services = build();
    engine.outlook = const CompressionOutlook(
      sizeBytes: 160000,
      pageCount: 30,
      imageCount: 0,
      pagesWithImages: 0,
    );
    await choose(tester);

    expect(find.text("This one probably won't shrink"), findsOneWidget);
    expect(find.textContaining('text and vector graphics'), findsOneWidget);
    // It must still be possible to try.
    expect(find.text('Compress'), findsWidgets);
  });

  testWidgets('no percentage is promised up front', (tester) async {
    await choose(tester);
    // "typically" is the strongest claim allowed before the run.
    expect(find.textContaining('typically'), findsOneWidget);
  });

  testWidgets('the level changes the quoted figure', (tester) async {
    await choose(tester);
    expect(find.textContaining('76%'), findsOneWidget);

    await tester.tap(find.text('Strong'));
    await tester.pumpAndSettle();
    expect(find.textContaining('98%'), findsOneWidget);
    expect(find.text('Smallest file'), findsOneWidget);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(find.textContaining('67%'), findsOneWidget);
  });

  testWidgets('says that text is never turned into pictures', (tester) async {
    await choose(tester);
    expect(find.textContaining('Text stays text'), findsOneWidget);
    expect(
      find.textContaining('selectable and searchable'),
      findsOneWidget,
    );
  });

  testWidgets('an import failure is explained', (tester) async {
    importer.failWith = const PdfFailure(FailureKind.tooLarge);
    await pump(tester);
    await tester.tap(find.text('Choose a PDF'));
    await tester.pumpAndSettle();

    expect(find.textContaining('too large'), findsOneWidget);
  });

  testWidgets('Balanced is the default', (tester) async {
    await choose(tester);
    final segmented = tester.widget<SegmentedButton<CompressionLevel>>(
      find.byType(SegmentedButton<CompressionLevel>),
    );
    expect(segmented.selected, {CompressionLevel.balanced});
  });
}
