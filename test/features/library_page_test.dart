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
}
