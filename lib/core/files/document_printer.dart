import 'dart:io';
import 'package:flutter/services.dart';

/// What came of handing a document to the platform's print system
/// (requirements.md 6).
enum PrintOutcome {
  /// The system print UI has the document. Whether the user then prints it,
  /// saves it as a PDF or backs out is between them and that UI, and is not
  /// something this app reports on.
  started,

  failed,

  /// No printing on this platform, or no print services configured.
  unsupported,
}

/// Sends a document to the platform print system (requirements.md 6).
abstract interface class DocumentPrinter {
  bool get isSupported;

  /// [pageCount] is passed on when known, so the print preview can show the
  /// real number instead of "unknown".
  Future<PrintOutcome> printDocument(File file, {String? jobName, int? pageCount});
}

/// Talks to a small amount of native code on each platform.
///
/// Deliberately not the `printing` package, for the same reason
/// [DeviceExporter] avoids `file_picker`'s `saveFile()`: its layout callback
/// hands the whole document over as bytes, and requirements.md 13 caps input
/// at 200 MB and peak RSS at 400 MB while requiring large documents to be
/// streamed. Android's PrintDocumentAdapter writes into a file descriptor and
/// iOS's UIPrintInteractionController takes a file URL, so neither platform
/// needs the bytes in memory at all.
class PlatformDocumentPrinter implements DocumentPrinter {
  const PlatformDocumentPrinter();

  static const _channel = MethodChannel('com.samir.pdf_toolbox/print');

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<PrintOutcome> printDocument(
    File file, {
    String? jobName,
    int? pageCount,
  }) async {
    if (!isSupported) return PrintOutcome.unsupported;
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('print', {
        'path': file.path,
        'jobName': jobName,
        'pageCount': pageCount,
      });
      return switch (reply?['status'] as String?) {
        'started' => PrintOutcome.started,
        'unsupported' => PrintOutcome.unsupported,
        _ => PrintOutcome.failed,
      };
    } on PlatformException {
      return PrintOutcome.failed;
    } on MissingPluginException {
      return PrintOutcome.unsupported;
    }
  }
}
