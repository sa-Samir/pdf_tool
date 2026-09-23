import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';

enum ImageFormat {
  png('PNG', 'png', 'Sharpest, largest files'),
  jpg('JPG', 'jpg', 'Smaller, good for photos');

  const ImageFormat(this.label, this.extension, this.hint);

  final String label;
  final String extension;
  final String hint;
}

/// Export resolutions offered (requirements.md 3.9).
enum ExportDpi {
  screen('Screen', 72),
  good('Good', 150),
  print('Print', 300);

  const ExportDpi(this.label, this.dpi);

  final String label;
  final int dpi;
}

/// What an export will produce, measured rather than guessed.
@immutable
class ExportEstimate {
  const ExportEstimate({
    required this.pageCount,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.bytesPerPage,
  });

  final int pageCount;
  final int pixelWidth;
  final int pixelHeight;

  /// Taken from actually rendering one page, so the total is within a few
  /// percent rather than a guess (requirements.md 3.9).
  final int bytesPerPage;

  int get totalBytes => bytesPerPage * pageCount;
}

/// Requirements.md 3.9: warn before producing more than this many files.
const kManyImagesThreshold = 100;

/// Renders one page to measure what a full export would cost.
Future<ExportEstimate> estimateExport({
  required AppServices services,
  required File source,
  required List<int> pageIndices,
  required ExportDpi dpi,
  required ImageFormat format,
}) async {
  final geometry = await services.engine.pageGeometry(source);
  final first = pageIndices.first.clamp(0, geometry.length - 1);
  final (width, height) = geometry[first].pixelsAt(dpi.dpi);

  final png = await services.engine.renderPageAt(
    input: source,
    pageIndex: first,
    pixelWidth: width,
    pixelHeight: height,
  );
  final bytes = format == ImageFormat.png
      ? png.length
      : (await services.images.toJpeg(png)).length;

  return ExportEstimate(
    pageCount: pageIndices.length,
    pixelWidth: width,
    pixelHeight: height,
    bytesPerPage: bytes,
  );
}

/// Exports pages as image files (requirements.md 3.9).
///
/// Cancelling removes everything written so far: a half-finished export is not
/// a result the user asked for.
Future<List<File>> exportPagesAsImages({
  required AppServices services,
  required File source,
  required List<int> pageIndices,
  required ExportDpi dpi,
  required ImageFormat format,
  required JobHandle handle,
}) async {
  final geometry = await services.engine.pageGeometry(source);
  final stem = p.basenameWithoutExtension(source.path);
  final folder = Directory(p.join(
    (await services.store.exports()).path,
    '$stem ${DateTime.now().millisecondsSinceEpoch}',
  ))
    ..createSync(recursive: true);

  final written = <File>[];
  try {
    for (var i = 0; i < pageIndices.length; i++) {
      handle.cancel.throwIfCancelled();
      handle.report(
        completed: i,
        total: pageIndices.length,
        label: 'Exporting page ${i + 1} of ${pageIndices.length}...',
      );

      final pageIndex = pageIndices[i];
      final (width, height) =
          geometry[pageIndex.clamp(0, geometry.length - 1)].pixelsAt(dpi.dpi);
      final png = await services.engine.renderPageAt(
        input: source,
        pageIndex: pageIndex,
        pixelWidth: width,
        pixelHeight: height,
        cancel: handle.cancel,
      );
      final bytes = format == ImageFormat.png
          ? png
          : await services.images.toJpeg(png);

      final file = File(p.join(
        folder.path,
        '${stem}_${(pageIndex + 1).toString().padLeft(3, '0')}'
            '.${format.extension}',
      ));
      await file.writeAsBytes(bytes, flush: true);
      written.add(file);
    }
    handle.report(
      completed: pageIndices.length,
      total: pageIndices.length,
      label: 'Done',
    );
    return written;
  } catch (_) {
    await _deleteQuietly(folder);
    rethrow;
  }
}

Future<void> _deleteQuietly(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } on FileSystemException {
    // Nothing useful to do.
  }
}
