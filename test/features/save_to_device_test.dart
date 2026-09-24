import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/files/device_exporter.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/library/library_document.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/library/library_page.dart';
import 'package:pdf_toolbox/features/shared/result_page.dart';
import 'package:pdf_toolbox/features/shared/save_to_device.dart';

import '../fakes.dart';

/// Everything the app writes lives in app-private storage and goes when the
/// app is uninstalled, so getting a copy out has to work and has to be
/// honest about what happened (requirements.md 6).
void main() {
  late FakeDeviceExporter exporter;
  late FakeLibraryRepository library;

  AppServices build([List<LibraryDocument> documents = const []]) {
    final engine = MemoryFakeEngine(const {});
    library = FakeLibraryRepository(documents);
    return AppServices(
      engine: engine,
      store: DocumentStore(engine: engine),
      importer: FakeFileImporter([]),
      library: library,
      gallery: FakeGallerySaver(),
      entitlements: FakeEntitlements(),
      deviceExport: exporter,
    );
  }

  setUp(() => exporter = FakeDeviceExporter());

  group('what the user is told', () {
    List<File> files(int n) =>
        [for (var i = 0; i < n; i++) File('/memory/doc$i.pdf')];

    test('one file names the file and where it went', () {
      final message = describeDeviceSave(
        const DeviceSaveResult(DeviceSaveStatus.saved,
            savedCount: 1, location: 'Download'),
        [File('/memory/report.pdf')],
      );
      expect(message, 'Saved report.pdf to Download.');
    });

    test('a destination we cannot name is left out, not invented', () {
      final message = describeDeviceSave(
        const DeviceSaveResult(DeviceSaveStatus.saved, savedCount: 1),
        [File('/memory/report.pdf')],
      );
      expect(message, 'Saved report.pdf.');
    });

    test('several files are counted', () {
      final message = describeDeviceSave(
        const DeviceSaveResult(DeviceSaveStatus.saved,
            savedCount: 3, location: 'Documents'),
        files(3),
      );
      expect(message, 'Saved 3 files to Documents.');
    });

    test('a partial save says so rather than rounding up to success', () {
      final message = describeDeviceSave(
        const DeviceSaveResult(DeviceSaveStatus.saved,
            savedCount: 2, location: 'Documents'),
        files(3),
      );
      expect(message, 'Saved 2 of 3 files to Documents.');
    });

    test('backing out of the picker is not announced at all', () {
      expect(
        describeDeviceSave(const DeviceSaveResult.cancelled(), files(2)),
        isNull,
        reason: 'cancelling is a choice, not an event',
      );
    });

    test('a failure names what failed', () {
      expect(
        describeDeviceSave(
          const DeviceSaveResult(DeviceSaveStatus.failed),
          [File('/memory/report.pdf')],
        ),
        'Could not save report.pdf.',
      );
      expect(
        describeDeviceSave(
          const DeviceSaveResult(DeviceSaveStatus.failed),
          files(3),
        ),
        'Could not save those 3 files.',
      );
    });

    test('an unsupported platform says so plainly', () {
      expect(
        describeDeviceSave(
          const DeviceSaveResult(DeviceSaveStatus.unsupported),
          files(1),
        ),
        contains('not supported'),
      );
    });
  });

  group('from a result', () {
    Future<void> pump(WidgetTester tester, {int fileCount = 1}) async {
      await tester.pumpWidget(AppServicesScope(
        services: build(),
        child: MaterialApp(
          home: ResultPage(
            title: 'Merged',
            files: [
              for (var i = 0; i < fileCount; i++) File('/memory/out$i.pdf'),
            ],
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a finished document can be copied out', (tester) async {
      await pump(tester);

      expect(find.text('Save to device'), findsOneWidget);
      await tester.tap(find.text('Save to device'));
      await tester.pump();

      expect(exporter.calls, hasLength(1));
      expect(exporter.lastCall, ['/memory/out0.pdf']);
    });

    testWidgets('several outputs go in one trip, and say so', (tester) async {
      await pump(tester, fileCount: 4);

      expect(find.text('Save 4 files to device'), findsOneWidget);
      await tester.tap(find.text('Save 4 files to device'));
      await tester.pump();

      expect(exporter.lastCall, hasLength(4));
    });
  });

  group('from Files', () {
    final sample = [
      fakeLibraryDocument('invoice.pdf'),
      fakeLibraryDocument('lease.pdf'),
      fakeLibraryDocument('notes.pdf'),
    ];

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(AppServicesScope(
        services: build(sample),
        child: const MaterialApp(home: LibraryPage()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('one document copies out from its menu', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('More actions for invoice.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to device'));
      await tester.pumpAndSettle();

      expect(exporter.calls, hasLength(1));
      expect(exporter.lastCall.single, endsWith('invoice.pdf'));
    });

    testWidgets('the library keeps its copy: this is a copy out, not a move',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('More actions for invoice.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to device'));
      await tester.pumpAndSettle();

      expect(await library.list(), hasLength(3));
      expect(find.text('invoice.pdf'), findsOneWidget);
    });

    testWidgets('a renamed document is copied out under its new name',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('More actions for invoice.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'invoice.pdf'),
        'quarterly.pdf',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions for quarterly.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to device'));
      await tester.pumpAndSettle();

      // Renaming moves the file, so the path handed to the exporter has to be
      // the new one. Resolving the old path would export a file that is no
      // longer there.
      expect(exporter.lastCall.single, endsWith('quarterly.pdf'));
    });

    testWidgets('a long press starts a selection', (tester) async {
      await pump(tester);

      await tester.longPress(find.text('invoice.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byTooltip('Save selected to device'), findsOneWidget);
    });

    testWidgets('several are copied out in one trip', (tester) async {
      await pump(tester);

      await tester.longPress(find.text('invoice.pdf'));
      await tester.pumpAndSettle();
      // Once a selection is running, a tap adds rather than opening.
      await tester.tap(find.text('notes.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Save selected to device'));
      await tester.pumpAndSettle();

      expect(exporter.calls, hasLength(1));
      expect(exporter.lastCall, hasLength(2));
      expect(
        exporter.lastCall.map((p) => p.split('/').last),
        containsAll(<String>['invoice.pdf', 'notes.pdf']),
      );
    });

    testWidgets('the selection clears once it has been saved', (tester) async {
      await pump(tester);

      await tester.longPress(find.text('invoice.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save selected to device'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Files'), findsOneWidget);
    });

    testWidgets('a selection can be abandoned without saving', (tester) async {
      await pump(tester);

      await tester.longPress(find.text('invoice.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsNothing);
      expect(exporter.calls, isEmpty);
    });
  });
}
