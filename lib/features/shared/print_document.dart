import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/files/document_printer.dart';
import '../../core/services/app_services.dart';

/// Sends [file] to the platform print system (requirements.md 6).
///
/// Needs a Scaffold above [context] for the report.
Future<PrintOutcome> printDocument(
  BuildContext context,
  File file, {
  int? pageCount,
}) async {
  final services = AppServicesScope.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final outcome = await services.printer.printDocument(
    file,
    jobName: p.basename(file.path),
    pageCount: pageCount,
  );
  final message = describePrint(outcome, file);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
  return outcome;
}

/// What to tell the user, or null when the honest answer is nothing.
String? describePrint(PrintOutcome outcome, File file) => switch (outcome) {
      // The system print UI is its own feedback, and it is still open. Saying
      // "sent to the printer" would claim an outcome this app cannot see: the
      // user may yet print, save as PDF, or back out.
      PrintOutcome.started => null,
      PrintOutcome.unsupported =>
        'Printing is not available on this device.',
      PrintOutcome.failed => 'Could not print ${p.basename(file.path)}.',
    };
