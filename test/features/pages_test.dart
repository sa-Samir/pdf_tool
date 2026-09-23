import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/merge/merge_page.dart';
import 'package:pdf_toolbox/features/split/split_page.dart';

import '../fakes.dart';

/// Widget tests cover what the screens show and enable. Running an operation
/// touches the filesystem, which never completes inside the fake-async zone a
/// widget test runs in, so the runs are covered in operations_test.dart.
void main() {
  late FakeFileImporter importer;
  late MemoryFakeEngine engine;
  late AppServices services;

  AppServices build(Map<String, int> pages) {
    engine = MemoryFakeEngine(pages);
    return AppServices(
      engine: engine,
      store: DocumentStore(engine: engine),
      importer: importer,
      library: FakeLibraryRepository(),
    );
  }

  setUp(() {
    importer = FakeFileImporter([]);
    services = build(const {});
  });

  /// `FilledButton.icon` builds a private subclass that `byType` will not match.
  Finder filledButton(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppServicesScope(
      services: services,
      child: MaterialApp(home: page),
    ));
    await tester.pumpAndSettle();
  }

  group('merge page', () {
    testWidgets('starts by asking for files', (tester) async {
      await pump(tester, const MergePage());
      expect(find.text('Combine PDFs into one'), findsOneWidget);
      expect(filledButton('Choose PDFs'), findsOneWidget);
    });

    testWidgets('lists chosen files with their page counts', (tester) async {
      services = build({'/memory/a.pdf': 3, '/memory/b.pdf': 4});
      importer.queued.add([memoryDocument('a.pdf'), memoryDocument('b.pdf')]);
      await pump(tester, const MergePage());

      await tester.tap(find.text('Choose PDFs'));
      await tester.pumpAndSettle();

      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.textContaining('3 pages'), findsOneWidget);
      expect(find.textContaining('4 pages'), findsOneWidget);
    });

    testWidgets('will not merge a single file', (tester) async {
      services = build({'/memory/only.pdf': 2});
      importer.queued.add([memoryDocument('only.pdf')]);
      await pump(tester, const MergePage());
      await tester.tap(find.text('Choose PDFs'));
      await tester.pumpAndSettle();

      expect(find.text('Add at least one more PDF to merge.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(filledButton('Merge 1 file')).onPressed,
        isNull,
      );
    });

    testWidgets('removing a file updates the count', (tester) async {
      services = build({
        '/memory/a.pdf': 1,
        '/memory/b.pdf': 1,
        '/memory/c.pdf': 1,
      });
      importer.queued.add([
        memoryDocument('a.pdf'),
        memoryDocument('b.pdf'),
        memoryDocument('c.pdf'),
      ]);
      await pump(tester, const MergePage());
      await tester.tap(find.text('Choose PDFs'));
      await tester.pumpAndSettle();
      expect(find.text('Merge 3 files'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove b.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('b.pdf'), findsNothing);
      expect(find.text('Merge 2 files'), findsOneWidget);
    });

    testWidgets('an import failure is explained, keeping the screen',
        (tester) async {
      importer.failWith = const PdfFailure(FailureKind.tooLarge);
      await pump(tester, const MergePage());

      await tester.tap(find.text('Choose PDFs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('too large'), findsOneWidget);
      expect(find.text('Your original file was not changed.'), findsOneWidget);
      expect(find.byType(MergePage), findsOneWidget);
    });
  });

  group('split page', () {
    Future<void> choose(WidgetTester tester, {int pages = 20}) async {
      services = build({'/memory/report.pdf': pages});
      importer.queued.add([memoryDocument('report.pdf')]);
      await pump(tester, const SplitPage());
      await tester.tap(find.text('Choose a PDF'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts by asking for a file', (tester) async {
      await pump(tester, const SplitPage());
      expect(find.text('Break a PDF apart'), findsOneWidget);
    });

    testWidgets('shows the page count and previews every-page output',
        (tester) async {
      await choose(tester, pages: 12);

      expect(find.textContaining('12 pages'), findsOneWidget);
      expect(find.textContaining('Creates 12 files'), findsOneWidget);
      expect(find.textContaining('report_1.pdf'), findsOneWidget);
    });

    testWidgets('a valid range previews the files it will create',
        (tester) async {
      await choose(tester);
      await tester.tap(find.text('Ranges'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1-5, 8');
      await tester.pumpAndSettle();

      expect(find.textContaining('Creates 2 files'), findsOneWidget);
      expect(find.textContaining('report_1-5.pdf'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(filledButton('Split')).onPressed,
        isNotNull,
      );
    });

    testWidgets('an invalid range is named and blocks the button',
        (tester) async {
      await choose(tester);
      await tester.tap(find.text('Ranges'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '5-2');
      await tester.pumpAndSettle();

      expect(find.text('"5-2" runs backwards. Try 2-5.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(filledButton('Split')).onPressed,
        isNull,
      );
    });

    testWidgets('a page past the end says how many pages there are',
        (tester) async {
      await choose(tester, pages: 6);
      await tester.tap(find.text('Ranges'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1-9');
      await tester.pumpAndSettle();

      expect(find.textContaining('has 6 pages'), findsOneWidget);
    });

    testWidgets('every-N chunks the document', (tester) async {
      await choose(tester, pages: 10);
      await tester.tap(find.text('Every N'));
      await tester.pumpAndSettle();

      // Default is 2 pages per file.
      expect(find.text('Pages per file: 2'), findsOneWidget);
      expect(find.textContaining('Creates 5 files'), findsOneWidget);

      await tester.tap(find.byTooltip('More pages per file'));
      await tester.pumpAndSettle();
      expect(find.text('Pages per file: 3'), findsOneWidget);
      expect(find.textContaining('Creates 4 files'), findsOneWidget);
    });
  });
}
