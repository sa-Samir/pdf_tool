import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/engine/pdf_engine.dart';
import '../../core/files/file_importer.dart';
import '../../core/images/page_layout.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';

/// One chosen image, with any rotation the user applied.
@immutable
class PickedImage {
  const PickedImage({required this.document, this.quarterTurns = 0});

  final ImportedDocument document;
  final int quarterTurns;

  String get name => document.displayName;

  PickedImage rotated(int turns) =>
      PickedImage(document: document, quarterTurns: (quarterTurns + turns) % 4);
}

/// Builds a PDF from images (requirements.md 3.8).
///
/// Images are normalised one at a time, so 50 photos never become 50 bitmaps
/// in memory.
Future<File> imagesToPdfDocument({
  required AppServices services,
  required List<PickedImage> images,
  required ImagePageOptions options,
  required JobHandle handle,
}) async {
  final workspace = await services.store.openWorkspace();
  try {
    final placed = <PlacedImage>[];
    final total = images.length + 1;

    for (var i = 0; i < images.length; i++) {
      handle.cancel.throwIfCancelled();
      handle.report(
        completed: i,
        total: total,
        label: 'Preparing image ${i + 1} of ${images.length}...',
      );

      final image = images[i];
      final normalized = await services.images.normalize(
        image.document.file,
        target: workspace.file('image-$i.jpg'),
        quality: options.quality,
        quarterTurns: image.quarterTurns,
      );
      placed.add(PlacedImage(
        file: normalized.file,
        placement: layoutImage(normalized, options),
      ));
    }

    handle.cancel.throwIfCancelled();
    handle.report(
      completed: images.length,
      total: total,
      label: 'Building the PDF...',
    );

    final temp = workspace.file('images.pdf');
    await services.engine.imagesToPdf(
      images: placed,
      output: temp,
      cancel: handle.cancel,
    );
    handle.cancel.throwIfCancelled();

    final stem = images.length == 1
        ? p.basenameWithoutExtension(images.first.name)
        : 'Images';
    final saved = await services.store.commit(
      temp,
      desiredName: '$stem.pdf',
      expectedPages: images.length,
    );
    await services.library.record(
      file: saved,
      operation: 'From ${images.length} image'
          '${images.length == 1 ? '' : 's'}',
      toolId: 'images_to_pdf',
      pageCount: images.length,
    );
    handle.report(completed: total, total: total, label: 'Done');
    return saved;
  } finally {
    await workspace.dispose();
  }
}
