import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/catalog/tool_catalog.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/models/pdf_tool.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/pages/page_grid_page.dart';
import 'package:pdf_toolbox/features/pages/widgets/page_tile.dart';

import '../fakes.dart';

/// UI states of the page grid. Saving touches the filesystem, which never
/// completes inside a widget test's fake-async zone, so the save path is
/// covered in operations_test.dart instead.
void main() {
  late FakeFileImporter importer;
  late MemoryFakeEngine engine;
  late AppServices services;

  PdfTool toolById(String id) =>
      ToolCatalog.all.firstWhere((t) => t.id == id);

  AppServices build(int pages) {
    engine = MemoryFakeEngine({'/memory/doc.pdf': pages});
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
    services = build(6);
  });

  Future<void> pump(WidgetTester tester, {String tool = 'reorder'}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppServicesScope(
      services: services,
      child: MaterialApp(home: PageGridPage(tool: toolById(tool))),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {String tool = 'reorder'}) async {
    importer.queued.add([memoryDocument('doc.pdf')]);
    await pump(tester, tool: tool);
    await tester.tap(find.text('Choose a PDF'));
    await tester.pumpAndSettle();
  }

  Future<void> tapPage(WidgetTester tester, int position) async {
    await tester.tap(find.bySemanticsLabel('Page $position'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts by asking for a file', (tester) async {
    await pump(tester);
    expect(find.text('Choose a PDF'), findsOneWidget);
  });

  for (final id in [
    'reorder',
    'rotate',
    'delete_pages',
    'duplicate',
    'extract',
  ]) {
    testWidgets('$id opens the shared page grid', (tester) async {
      services = build(3);
      await open(tester, tool: id);
      expect(find.byType(PageTile), findsNWidgets(3));
    });
  }

  testWidgets('shows one tile per page', (tester) async {
    await open(tester);
    expect(find.byType(PageTile), findsNWidgets(6));
    expect(find.text('No changes yet'), findsOneWidget);
  });

  testWidgets('selecting a page shows the count in the title',
      (tester) async {
    await open(tester);
    await tapPage(tester, 1);
    expect(find.text('1 selected'), findsOneWidget);
    await tapPage(tester, 3);
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('page actions are disabled until something is selected',
      (tester) async {
    await open(tester);
    final rotate = tester.widget<InkWell>(
      find.ancestor(
        of: find.text('Right'),
        matching: find.byType(InkWell),
      ),
    );
    expect(rotate.onTap, isNull);
  });

  testWidgets('deleting pages updates the grid and the save label',
      (tester) async {
    await open(tester);
    await tapPage(tester, 2);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsNWidgets(5));
    expect(find.text('Save 5 pages'), findsOneWidget);
  });

  testWidgets('duplicating adds a page next to its original', (tester) async {
    await open(tester);
    await tapPage(tester, 1);
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsNWidgets(7));
    expect(find.text('Save 7 pages'), findsOneWidget);
  });

  testWidgets('keep-only reduces the document to the selection',
      (tester) async {
    await open(tester);
    await tapPage(tester, 2);
    await tapPage(tester, 4);
    await tester.tap(find.text('Keep only'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsNWidgets(2));
  });

  testWidgets('deleting every page is refused', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();

    final delete = tester.widget<InkWell>(
      find.ancestor(of: find.text('Delete'), matching: find.byType(InkWell)),
    );
    expect(delete.onTap, isNull);
    expect(find.byType(PageTile), findsNWidgets(6));
  });

  testWidgets('undo reverses an edit and redo replays it', (tester) async {
    await open(tester);
    await tapPage(tester, 1);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(PageTile), findsNWidgets(5));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(PageTile), findsNWidgets(6));

    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(find.byType(PageTile), findsNWidgets(5));
  });

  testWidgets('undo is disabled before any edit', (tester) async {
    await open(tester);
    final undo = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Undo'),
        matching: find.byType(IconButton),
      ),
    );
    expect(undo.onPressed, isNull);
  });

  testWidgets('select all toggles to clear', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('6 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    expect(find.text('Reorder pages'), findsOneWidget);
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    await open(tester);
    await tapPage(tester, 1);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(PageGridPage));
    Navigator.of(context).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(
      find.textContaining('original file is untouched'),
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
}
