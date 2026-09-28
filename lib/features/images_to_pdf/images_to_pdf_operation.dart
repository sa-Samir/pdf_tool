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

/// Where a set of images came from.
///
/// The only thing that differs between picking photos and scanning paper is
/// what the result is called and how the library records it. Everything after
/// that -- normalise, lay out, build, verify, commit -- is one pipeline, so
/// the difference is data rather than a second copy of the code.
enum ImageSource {
  picked(
    title: 'Images to PDF',
    toolId: 'images_to_pdf',
    stem: 'Images',
    emptyHeadline: 'Turn photos into a PDF',
    emptyHint: 'One image per page. You can reorder and rotate them first.',
    addLabel: 'Choose images',
  ),
  scanned(
    title: 'Scan document',
    toolId: 'scan',
    stem: 'Scan',
    emptyHeadline: 'Scan paper with the camera',
    emptyHint: 'Edges are found and straightened for you. '
        'Capture as many pages as you need.',
    addLabel: 'Open the scanner',
  );

  const ImageSource({
    required this.title,
    required this.toolId,
    required this.stem,
    required this.emptyHeadline,
    required this.emptyHint,
    required this.addLabel,
  });

  final String title;
  final String toolId;

  /// Default file-name stem for the result.
  final String stem;

  final String emptyHeadline;
  final String emptyHint;
  final String addLabel;

  /// How the library describes the result.
  String describe(int count) => switch (this) {
        ImageSource.picked => 'From $count image${count == 1 ? '' : 's'}',
        ImageSource.scanned => 'Scanned $count page${count == 1 ? '' : 's'}',
      };
}

/// Builds a PDF from images (requirements.md 3.8, and 3.10 for scans).
///
/// Images are normalised one at a time, so 50 photos never become 50 bitmaps
/// in memory.
Future<File> imagesToPdfDocument({
  required AppServices services,
  required List<PickedImage> images,
  required ImagePageOptions options,
  required JobHandle handle,
  ImageSource source = ImageSource.picked,
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

    // A single picked photo keeps its own name; a scan is always "Scan",
    // because the platform scanner's page file names mean nothing to anyone.
    final stem = source == ImageSource.picked && images.length == 1
        ? p.basenameWithoutExtension(images.first.name)
        : source.stem;
    final saved = await services.store.commit(
      temp,
      desiredName: '$stem.pdf',
      expectedPages: images.length,
    );
    await services.library.record(
      file: saved,
      operation: source.describe(images.length),
      toolId: source.toolId,
      pageCount: images.length,
    );
    handle.report(completed: total, total: total, label: 'Done');
    return saved;
  } finally {
    await workspace.dispose();
  }
}
