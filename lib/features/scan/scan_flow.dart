import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/entitlements/entitlements.dart';
import '../../core/entitlements/tool_limits.dart';
import '../../core/files/file_importer.dart';
import '../../core/scan/document_scanner.dart';
import '../../core/services/app_services.dart';
import '../images_to_pdf/images_to_pdf_operation.dart';
import '../images_to_pdf/images_to_pdf_page.dart';

/// Wraps captured pages so the images pipeline can take them.
///
/// Pure on purpose: no file I/O, so a widget test can drive the whole scan
/// flow without hanging in its fake-async zone.
List<PickedImage> pickedFromScan(ScanResult result) => [
      for (final page in result.pages)
        PickedImage(
          document: ImportedDocument(
            file: page.file,
            displayName: p.basename(page.file.path),
            sizeBytes: page.sizeBytes,
          ),
        ),
    ];

/// Trims a capture to what the free tier allows (requirements.md 9).
///
/// Applied here rather than handed to the scanner: the platform scanners do
/// not all honour a page limit, so trimming afterwards is the only way the
/// number on the card actually holds.
({List<PickedImage> accepted, bool capped}) capScan(
  AppServices services, {
  required List<PickedImage> captured,
  int existing = 0,
}) {
  if (services.entitlements.isUnrestricted) {
    return (accepted: captured, capped: false);
  }
  final room =
      (ToolLimits.scannerFreePages - existing).clamp(0, captured.length);
  return (
    accepted: captured.take(room).toList(),
    capped: room < captured.length,
  );
}

/// What to tell the user about a scan, or null when the honest answer is
/// nothing.
String? describeScan(ScanResult result) => switch (result.outcome) {
      // Backing out of the camera is a choice, not an event.
      ScanOutcome.cancelled => null,
      ScanOutcome.captured when result.pages.isEmpty =>
        'The scanner returned no pages.',
      ScanOutcome.captured => null,
      ScanOutcome.unavailable => 'Scanning is not available on this device.',
      ScanOutcome.failed => 'The scanner could not be opened.',
    };

/// The message shown when a capture is trimmed by the free tier.
String get scanCappedMessage =>
    'The free version scans up to ${ToolLimits.scannerFreePages} pages '
    'at a time.';

/// Runs a scan from a tool tap: camera first, then the review screen
/// (requirements.md 3.10).
///
/// Nothing is pushed unless pages were actually captured, so backing out of
/// the camera leaves the user where they were rather than on an empty screen
/// they have to dismiss.
Future<void> startScan(BuildContext context) async {
  final services = AppServicesScope.of(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final result = await services.scanner.scan();
  final message = describeScan(result);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
  if (!result.hasPages) return;

  final capped = capScan(services, captured: pickedFromScan(result));
  if (capped.capped) {
    messenger.showSnackBar(SnackBar(content: Text(scanCappedMessage)));
  }
  if (capped.accepted.isEmpty) return;

  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ImagesToPdfPage(
        source: ImageSource.scanned,
        initial: capped.accepted,
      ),
    ),
  );
}
