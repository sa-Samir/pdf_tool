import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/files/save_target.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/shared/result_page.dart';

import '../fakes.dart';

/// The undo affordance is the whole reason replacing is allowed without
/// asking first (requirements.md 5.2), so what the screen offers is tested.
void main() {
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
    );
  });

  /// Paths only: nothing here reads them, and real I/O would never complete
  /// inside a widget test's fake-async zone.
  ReplacedVersion version({String name = 'report.pdf'}) => ReplacedVersion(
        replacement: Replacement(
          file: File('/memory/$name'),
          previous: File('/memory/revisions/$name'),
        ),
        documentId: 'doc-1',
        documentName: name,
        previousOperation: 'Merged',
        previousPageCount: 5,
      );

  Future<void> pump(
    WidgetTester tester, {
    ReplacedVersion? undo,
    UndoAction? action,
  }) async {
    await tester.pumpWidget(AppServicesScope(
      services: services,
      child: MaterialApp(
        home: ResultPage(
          title: 'Reorder pages',
          files: [File('/memory/report.pdf')],
          summary: '5 pages saved',
          undo: undo,
          undoAction: action ?? (_, _) async {},
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a replace says what it replaced and offers it back',
      (tester) async {
    await pump(tester, undo: version());

    expect(find.text('Replaced report.pdf'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Undo'), findsOneWidget);
  });

  testWidgets('it says how long the previous version lasts', (tester) async {
    await pump(tester, undo: version());

    // The retention window is a promise; the screen must state the real one.
    expect(
      find.text('The previous version is kept for ${kRevisionMaxAge.inDays} '
          'days.'),
      findsOneWidget,
    );
  });

  testWidgets('a new file overwrote nothing, so offers no undo',
      (tester) async {
    await pump(tester);

    expect(find.text('Undo'), findsNothing);
    expect(find.textContaining('Replaced'), findsNothing);
    expect(find.text('5 pages saved'), findsOneWidget);
  });

  testWidgets('the document name is not truncated out of the offer',
      (tester) async {
    await pump(tester, undo: version(name: 'Q3 board pack final.pdf'));

    expect(find.text('Replaced Q3 board pack final.pdf'), findsOneWidget);
  });

  group('taking the offer', () {
    testWidgets('hands the right version to the undo and confirms it',
        (tester) async {
      ReplacedVersion? undone;
      await pump(
        tester,
        undo: version(),
        action: (_, v) async => undone = v,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(undone?.documentId, 'doc-1');
      expect(find.text('Previous version restored'), findsOneWidget);
      expect(find.text('report.pdf is back as it was.'), findsOneWidget);
    });

    testWidgets('cannot be taken twice, because the revision is consumed',
        (tester) async {
      var calls = 0;
      await pump(
        tester,
        undo: version(),
        action: (_, _) async => calls++,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('says so when it fails instead of claiming success',
        (tester) async {
      await pump(
        tester,
        undo: version(),
        action: (_, _) async => throw const FileSystemException('gone'),
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Could not undo'), findsOneWidget);
      expect(find.text('Previous version restored'), findsNothing);
      // The new version is still there and still usable; say that plainly.
      expect(find.textContaining('still holds the new content'), findsOneWidget);
    });
  });
}