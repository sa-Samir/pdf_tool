import 'dart:io';

import 'package:flutter/foundation.dart';

import '../images/page_layout.dart';
import '../jobs/cancel_token.dart';
import '../pages/page_edit_session.dart';
import 'compression.dart';

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

  /// Renders one page to PNG bytes, bounded by [maxSize] pixels on the longer
  /// edge. Used for grid thumbnails, so it is called a lot and must stay cheap.
  Future<Uint8List> renderPage({
    required File input,
    required int pageIndex,
    required int maxSize,
    CancelToken? cancel,
    String? password,
  });

  /// Writes [pages] to [output] in the given order, applying each page's
  /// rotation.
  ///
  /// One call for a whole edit session: the user reorders, rotates, deletes and
  /// duplicates freely, and this saves the result once (requirements.md 3.6).
  /// [pages] may repeat a source index (a duplicated page) and may omit one (a
  /// deleted page).
  Future<void> applyPageEdits({
    required File input,
    required File output,
    required List<PageRef> pages,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  });

  /// Reads what can be known instantly about how compressible a document is.
  Future<CompressionOutlook> inspectForCompression(
    File input, {
    CancelToken? cancel,
    String? password,
  });

  /// Re-encodes embedded raster images and repacks streams.
  ///
  /// Text and vector content is never rasterized, so the result stays
  /// selectable and searchable (requirements.md 3.7).
  Future<CompressionResult> compress({
    required File input,
    required File output,
    required CompressionLevel level,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  });

  /// The size of each page, in PDF points. Used to turn a DPI into pixels and
  /// to estimate export sizes (requirements.md 3.9).
  Future<List<PageGeometry>> pageGeometry(
    File input, {
    CancelToken? cancel,
    String? password,
  });

  /// Builds a PDF from already-normalised images, one page each.
  Future<void> imagesToPdf({
    required List<PlacedImage> images,
    required File output,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
  });

  /// Renders one page at an explicit pixel size, for export
  /// (requirements.md 3.9).
  Future<Uint8List> renderPageAt({
    required File input,
    required int pageIndex,
    required int pixelWidth,
    required int pixelHeight,
    CancelToken? cancel,
    String? password,
  });

  Future<void> dispose();
}

/// One page's size, in PDF points.
@immutable
class PageGeometry {
  const PageGeometry({required this.width, required this.height});

  final double width;
  final double height;

  /// Pixel size at [dpi]. PDF points are 1/72 inch.
  (int, int) pixelsAt(int dpi) =>
      ((width / 72 * dpi).round(), (height / 72 * dpi).round());
}

/// An image with the page and rectangle it should occupy.
@immutable
class PlacedImage {
  const PlacedImage({required this.file, required this.placement});

  final File file;
  final PagePlacement placement;
}
