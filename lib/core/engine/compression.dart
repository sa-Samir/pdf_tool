import 'package:flutter/foundation.dart';

/// Compression presets (requirements.md 3.7).
///
/// The percentages in [typicalSavingOnScans] are measured, not guessed --
/// see docs/benchmarks.md. They describe image-heavy documents only; a text
/// PDF saves nothing at any level.
enum CompressionLevel {
  light('Light', 'Best quality', 67),
  balanced('Balanced', 'Recommended', 76),
  strong('Strong', 'Smallest file', 98);

  const CompressionLevel(this.label, this.hint, this.typicalSavingOnScans);

  final String label;
  final String hint;

  /// Rough percentage saved on a scanned document at this level.
  final int typicalSavingOnScans;
}

/// What can be known about a document instantly, before compressing it.
///
/// Deliberately not a predicted percentage. Savings track image *bytes*, and
/// there is no cheap way to read those ahead of the run, so guessing a number
/// here would mislead (docs/benchmarks.md).
@immutable
class CompressionOutlook {
  const CompressionOutlook({
    required this.sizeBytes,
    required this.pageCount,
    required this.imageCount,
    required this.pagesWithImages,
  });

  final int sizeBytes;
  final int pageCount;

  /// Raster images found across the document.
  final int imageCount;
  final int pagesWithImages;

  /// Whether compressing is worth offering at all. A document with no raster
  /// images has nothing for this tool to work on.
  bool get likelyToShrink => imageCount > 0;
}

/// The measured result of a compression run.
@immutable
class CompressionResult {
  const CompressionResult({
    required this.originalBytes,
    required this.compressedBytes,
  });

  final int originalBytes;
  final int compressedBytes;

  int get savedBytes => originalBytes - compressedBytes;

  double get savedFraction =>
      originalBytes == 0 ? 0 : savedBytes / originalBytes;

  int get savedPercent => (savedFraction * 100).round();

  /// Requirements.md 3.7: under 5% is reported as "already optimized" rather
  /// than dressed up as a saving, and it costs the user nothing.
  bool get isNoOp => savedFraction < 0.05;
}
