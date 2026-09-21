import 'dart:io';

import 'package:flutter/foundation.dart';

import '../jobs/cancel_token.dart';

/// What we know about a PDF without opening it in the UI.
@immutable
class PdfDocumentInfo {
  const PdfDocumentInfo({required this.pageCount, required this.sizeBytes});

  final int pageCount;
  final int sizeBytes;
}

/// The single seam between the app and whichever PDF library is underneath
/// (requirements.md 17).
///
/// No feature or UI code may import the PDF package directly. Everything goes
/// through this interface, so swapping the engine is a one-file change and the
/// features can be tested against a fake.
abstract interface class PdfEngine {
  /// Reads structure only. Throws [PdfFailure] on a file we cannot handle.
  Future<PdfDocumentInfo> inspect(File file, {String? password});

  /// Concatenates [inputs] into [output], in order.
  ///
  /// [onStep] reports completed inputs, so the UI can show "file 3 of 7". The
  /// engine itself reports no progress, so step counting is the honest
  /// granularity available (requirements.md 13).
  Future<void> merge({
    required List<File> inputs,
    required File output,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  });

  /// Writes the given zero-based [pageIndices] of [input] to [output].
  Future<void> extractPages({
    required File input,
    required File output,
    required List<int> pageIndices,
    CancelToken? cancel,
    String? password,
  });

  Future<void> dispose();
}
