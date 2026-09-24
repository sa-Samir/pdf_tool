import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/files/document_printer.dart';
import 'package:pdf_toolbox/core/files/document_store.dart';
import 'package:pdf_toolbox/core/library/library_document.dart';
import 'package:pdf_toolbox/core/services/app_services.dart';
import 'package:pdf_toolbox/features/library/library_page.dart';
import 'package:pdf_toolbox/features/shared/print_document.dart';

import '../fakes.dart';

/// Printing is the last of the section 6 actions. What it must not do is claim
/// an outcome it cannot see: the system print UI is still open when we return.
void main() {
  late FakeDocumentPrinter printer;
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
      printer: printer,
    );
  }

  setUp(() => printer = FakeDocumentPrinter());

  group('what the user is told', () {
    final file = File('/memory/report.pdf');

    test('a document handed to the print UI is not announced', () {
      // That UI is its own feedback and is still on screen. "Sent to the
      // printer" would claim an outcome this app cannot see.
      expect(describePrint(PrintOutcome.started, file), isNull);
    });

    test('a device that cannot print says so', () {
      expect(
        describePrint(PrintOutcome.unsupported, file),
        'Printing is not available on this device.',
      );
    });

    test('a failure names the document', () {
      expect(
        describePrint(PrintOutcome.failed, file),
        'Could not print report.pdf.',
      );
    });
  });

  group('from Files', () {
    final sample = [fakeLibraryDocument('invoice.pdf', pageCount: 12)];

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

    Future<void> tapPrint(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More actions for invoice.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();
    }

    testWidgets('a document can be printed from its menu', (tester) async {
      await pump(tester);
      await tapPrint(tester);

      expect(printer.jobs, hasLength(1));
      expect(printer.jobs.single.path, endsWith('invoice.pdf'));
    });

    testWidgets('the known page count is passed on to the print preview',
        (tester) async {
      await pump(tester);
      await tapPrint(tester);

      // Without this the preview shows "unknown", though the library has had
      // the real number all along.
      expect(printer.jobs.single.pageCount, 12);
      expect(printer.jobs.single.jobName, endsWith('invoice.pdf'));
    });

    testWidgets('a device that cannot print says so rather than failing quietly',
        (tester) async {
      printer.outcome = PrintOutcome.unsupported;
      await pump(tester);
      await tapPrint(tester);

      expect(
        find.text('Printing is not available on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('handing off to the print UI shows no message at all',
        (tester) async {
      await pump(tester);
      await tapPrint(tester);

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a document whose file has gone says so instead of printing',
        (tester) async {
      await pump(tester);
      library.filesMissing = true;
      await tapPrint(tester);

      expect(printer.jobs, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
