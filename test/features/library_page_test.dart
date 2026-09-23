import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/library/library_document.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/library/library_page.dart';

import '../fakes.dart';

void main() {
  late FakeLibraryRepository library;
  late AppServices services;

  AppServices build(List<LibraryDocument> documents) {
    final engine = MemoryFakeEngine(const {});
    library = FakeLibraryRepository(documents);
    return AppServices(
      engine: engine,
      store: DocumentStore(engine: engine),
      importer: FakeFileImporter([]),
      library: library,
      gallery: FakeGallerySaver(),
    );
  }

  Future<void> pump(WidgetTester tester, List<LibraryDocument> docs) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    services = build(docs);
    await tester.pumpWidget(AppServicesScope(
      services: services,
      child: const MaterialApp(home: LibraryPage()),
    ));
    await tester.pumpAndSettle();
  }

  final sample = [
    fakeLibraryDocument('invoice.pdf',
        operation: 'Merged from 3 files', sizeBytes: 2400000),
    fakeLibraryDocument('lease_1-5.pdf',
        operation: 'Split', sizeBytes: 900000, favorite: true),
    fakeLibraryDocument('notes.pdf', operation: 'Edited pages'),
  ];

  testWidgets('lists what the app has produced', (tester) async {
    await pump(tester, sample);
    expect(find.text('invoice.pdf'), findsOneWidget);
    expect(find.text('lease_1-5.pdf'), findsOneWidget);
    expect(find.textContaining('Merged from 3 files'), findsOneWidget);
  });

  testWidgets('empty state explains what fills it', (tester) async {
    await pump(tester, const []);
    expect(find.text('No files yet'), findsOneWidget);
    expect(
      find.textContaining('merge, split or edit'),
      findsOneWidget,
    );
  });

  testWidgets('search filters by name and explains an empty result',
      (tester) async {
    await pump(tester, sample);
    await tester.enterText(find.byType(TextField), 'lease');
    await tester.pumpAndSettle();
    expect(find.text('lease_1-5.pdf'), findsOneWidget);
    expect(find.text('invoice.pdf'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches that'), findsOneWidget);
  });

  testWidgets('favourites can be filtered, with their own empty state',
      (tester) async {
    await pump(tester, sample);
    await tester.tap(find.byTooltip('Favourites only'));
    await tester.pumpAndSettle();

    expect(find.text('lease_1-5.pdf'), findsOneWidget);
    expect(find.text('invoice.pdf'), findsNothing);
  });

  testWidgets('a star toggles and persists to the repository',
      (tester) async {
    await pump(tester, sample);
    await tester.tap(find.byTooltip('Add invoice.pdf to favourites'));
    await tester.pumpAndSettle();

    final stored = await library.byId('invoice.pdf');
    expect(stored!.favorite, isTrue);
    expect(find.byTooltip('Remove invoice.pdf from favourites'),
        findsOneWidget);
  });

  testWidgets('sorting by name reorders the list', (tester) async {
    await pump(tester, sample);
    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    final names = [for (final t in tiles) (t.title! as Text).data];
    expect(names, ['invoice.pdf', 'lease_1-5.pdf', 'notes.pdf']);
  });

  testWidgets('renaming updates the list', (tester) async {
    await pump(tester, sample);
    await tester.tap(find.byTooltip('More actions for notes.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'notes.pdf'),
      'meeting notes.pdf',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text('meeting notes.pdf'), findsOneWidget);
    expect(find.text('notes.pdf'), findsNothing);
  });

  testWidgets('deleting asks first, and says it cannot be undone',
      (tester) async {
    await pump(tester, sample);
    await tester.tap(find.byTooltip('More actions for invoice.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete invoice.pdf?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('invoice.pdf'), findsNothing);
  });

  testWidgets('cancelling a delete keeps the file', (tester) async {
    await pump(tester, sample);
    await tester.tap(find.byTooltip('More actions for invoice.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('invoice.pdf'), findsOneWidget);
  });

  testWidgets('a file that has gone says so instead of failing silently',
      (tester) async {
    await pump(tester, sample);
    library.filesMissing = true;

    await tester.tap(find.text('invoice.pdf'));
    await tester.pumpAndSettle();

    expect(
      find.text('That file is no longer on this device.'),
      findsOneWidget,
    );
  });

  group('folders', () {
    testWidgets('a new folder appears in the list', (tester) async {
      await pump(tester, sample);
      await tester.tap(find.byTooltip('New folder'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Contracts');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Contracts'), findsOneWidget);
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('opening a folder shows only its contents', (tester) async {
      await pump(tester, sample);
      final folder = await library.createFolder('Invoices');
      await library.moveToFolder('invoice.pdf', folder.id);
      await tester.tap(find.byTooltip('Favourites only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show all'));
      await tester.pumpAndSettle();

      // At the root, a filed document is not listed; the folder is.
      expect(find.text('Invoices'), findsOneWidget);
      expect(find.text('invoice.pdf'), findsNothing);

      await tester.tap(find.text('Invoices'));
      await tester.pumpAndSettle();
      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('notes.pdf'), findsNothing);
    });

    testWidgets('an empty folder says how to fill it', (tester) async {
      await pump(tester, const []);
      await library.createFolder('Empty one');
      await tester.tap(find.byTooltip('Favourites only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show all'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Empty one'));
      await tester.pumpAndSettle();
      expect(find.text('This folder is empty'), findsOneWidget);
    });

    testWidgets('deleting a folder warns that the files stay',
        (tester) async {
      await pump(tester, sample);
      await library.createFolder('Doomed');
      await tester.tap(find.byTooltip('Favourites only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show all'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions for Doomed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete folder'));
      await tester.pumpAndSettle();

      expect(find.textContaining('the files in it stay'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete folder'));
      await tester.pumpAndSettle();
      expect(find.text('Doomed'), findsNothing);
    });

    testWidgets('a document can be moved into a folder', (tester) async {
      await pump(tester, sample);
      await library.createFolder('Filed');
      await tester.tap(find.byTooltip('Favourites only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show all'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions for notes.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to folder'));
      await tester.pumpAndSettle();
      // The folder name also shows in the list behind the sheet.
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Filed'),
      ));
      await tester.pumpAndSettle();

      final moved = await library.byId('notes.pdf');
      expect(moved!.folderId, isNotNull);
      expect(find.text('notes.pdf'), findsNothing);
    });

    testWidgets('searching looks inside folders too', (tester) async {
      await pump(tester, sample);
      final folder = await library.createFolder('Hidden');
      await library.moveToFolder('invoice.pdf', folder.id);
      await tester.tap(find.byTooltip('Favourites only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show all'));
      await tester.pumpAndSettle();
      expect(find.text('invoice.pdf'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'invoice');
      await tester.pumpAndSettle();
      expect(find.text('invoice.pdf'), findsOneWidget);
    });
  });
}
