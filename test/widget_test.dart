import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_toolbox/app/app.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/library/library_document.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/compress/compress_page.dart';
import 'package:pdf_toolbox/features/images_to_pdf/images_to_pdf_page.dart';
import 'package:pdf_toolbox/features/pdf_to_images/pdf_to_images_page.dart';
import 'package:pdf_toolbox/features/merge/merge_page.dart';
import 'package:pdf_toolbox/features/pages/page_grid_page.dart';
import 'package:pdf_toolbox/core/catalog/tool_catalog.dart';
import 'package:pdf_toolbox/core/models/pdf_tool.dart';
import 'package:pdf_toolbox/features/home/home_page.dart';
import 'package:pdf_toolbox/features/tool/tool_placeholder_page.dart';

import 'fakes.dart';

late FakeLibraryRepository library;

AppServices _services() {
  final engine = MemoryFakeEngine(const {});
  library = FakeLibraryRepository();
  return AppServices(
    engine: engine,
    store: DocumentStore(engine: engine),
    importer: FakeFileImporter([]),
    library: library,
  );
}

Widget _host(
  Widget child, {
  List<LibraryDocument> recents = const [],
  Duration listDelay = Duration.zero,
}) {
  final engine = MemoryFakeEngine(const {});
  library = FakeLibraryRepository(recents)..listDelay = listDelay;
  return AppServicesScope(
    services: AppServices(
      engine: engine,
      store: DocumentStore(engine: engine),
      importer: FakeFileImporter([]),
      library: library,
      gallery: FakeGallerySaver(),
    ),
    child: MaterialApp(home: child),
  );
}

/// Pumps the home screen on a surface tall enough to build every tool group.
/// Slivers do not build off-screen children, so the default 800x600 test
/// viewport would hide the lower groups from the finders.
Future<void> _pumpHome(
  WidgetTester tester, {
  List<LibraryDocument> recents = const [],
  Duration listDelay = Duration.zero,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _host(const HomePage(), recents: recents, listDelay: listDelay),
  );
}

void main() {
  group('tool catalog', () {
    test('only ships tools at or before the current release', () {
      final shipped = ToolCatalog.shipped.map((t) => t.id).toSet();
      expect(shipped, contains('merge'));
      expect(shipped, contains('compress'));
      // requirements.md 3.1: unshipped tools are not displayed at all.
      expect(shipped, isNot(contains('scan')));
      expect(shipped, isNot(contains('protect')));
      expect(shipped, isNot(contains('annotate')));
    });

    test('search matches the verbs users type, not only tool names', () {
      String? idFor(String query) {
        final hits = ToolCatalog.grouped(query: query).values.expand((e) => e);
        return hits.length == 1 ? hits.single.id : null;
      }

      expect(idFor('shrink'), 'compress');
      expect(idFor('combine'), 'merge');
      expect(idFor('rearrange'), 'reorder');
      expect(idFor('heic'), 'images_to_pdf');
    });

    test('search is case-insensitive and ignores surrounding space', () {
      expect(ToolCatalog.grouped(query: '  ShRiNk ').values.single.single.id,
          'compress');
    });

    test('unshipped tools stay out of search results', () {
      // "password" only matches Protect and Unlock, both v1.3.
      expect(ToolCatalog.grouped(query: 'password'), isEmpty);
    });

    test('every tool declares a description and at least one alias', () {
      for (final tool in ToolCatalog.all) {
        expect(tool.description, isNotEmpty, reason: tool.id);
        expect(tool.aliases, isNotEmpty, reason: tool.id);
      }
    });

    test('tool ids are unique', () {
      final ids = ToolCatalog.all.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('a limit is stated wherever one applies', () {
      for (final tool in ToolCatalog.all) {
        if (tool.tier == ToolTier.freeWithLimit) {
          expect(tool.tierNote, isNotNull, reason: tool.id);
        }
        if (tool.tier == ToolTier.free) {
          expect(tool.tierNote, isNull, reason: tool.id);
        }
      }
    });
  });

  group('home screen', () {
    testWidgets('is interactive before recents finish loading', (tester) async {
      await _pumpHome(tester, listDelay: const Duration(seconds: 2));
      await tester.pump();

      // Recents are still loading...
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // ...while the rest of the screen is already usable.
      expect(find.text('Merge'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'shrink');
      await tester.pump();
      expect(find.text('Compress'), findsOneWidget);
      expect(find.text('Merge'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('shows the empty state with its action when there are no recents',
        (tester) async {
      await _pumpHome(tester);
      await tester.pumpAndSettle();

      expect(find.text('No recent files yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
    });

    testWidgets('renders shipped tools and hides unshipped ones',
        (tester) async {
      await _pumpHome(tester);
      await tester.pumpAndSettle();

      expect(find.text('Organize'), findsOneWidget);
      expect(find.text('Compress'), findsOneWidget);
      expect(find.text('Scan document'), findsNothing);
      expect(find.text('Capture'), findsNothing);
      expect(find.text('Secure'), findsNothing);
    });

    testWidgets('states a limit only where one applies', (tester) async {
      await _pumpHome(tester);
      await tester.pumpAndSettle();

      expect(find.text('Up to 3 files'), findsOneWidget); // Merge
      expect(find.text('3 free uses'), findsOneWidget); // Compress
    });

    testWidgets('lists recent documents once they load', (tester) async {
      await _pumpHome(tester, recents: [
        fakeLibraryDocument('invoice.pdf', operation: 'Compressed'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('Compressed'), findsOneWidget);
      expect(find.text('No recent files yet'), findsNothing);
    });

    testWidgets('search with no match explains itself', (tester) async {
      await _pumpHome(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No tool matches'), findsOneWidget);
    });

    testWidgets('opens a built tool for real', (tester) async {
      await _pumpHome(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      expect(find.byType(MergePage), findsOneWidget);
    });

    // Every v1.0 tool is now built, so nothing shipped reaches the
    // placeholder. It stays for the tools that arrive in later releases.
    for (final entry in {
      'Compress': CompressPage,
      'Images to PDF': ImagesToPdfPage,
      'PDF to images': PdfToImagesPage,
    }.entries) {
      testWidgets('${entry.key} opens its own screen', (tester) async {
        await _pumpHome(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.byType(entry.value), findsOneWidget);
      });
    }

    testWidgets('no shipped tool lands on the placeholder', (tester) async {
      await _pumpHome(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ToolPlaceholderPage), findsNothing);
    });

    // One test each: a loop inside a single testWidgets would keep the pushed
    // route from the previous iteration.
    for (final label in [
      'Rotate pages',
      'Delete pages',
      'Reorder pages',
      'Duplicate pages',
      'Extract pages',
    ]) {
      testWidgets('$label opens the page grid', (tester) async {
        await _pumpHome(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(PageGridPage), findsOneWidget);
      });
    }
  });

  group('app', () {
    testWidgets('boots to the home screen', (tester) async {
      await tester.pumpWidget(PdfToolboxApp(services: _services()));
      await tester.pumpAndSettle();
      expect(find.text('PDF Toolbox'), findsOneWidget);
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('theme can be switched from settings', (tester) async {
      await tester.pumpWidget(PdfToolboxApp(services: _services()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
    });
  });
}
