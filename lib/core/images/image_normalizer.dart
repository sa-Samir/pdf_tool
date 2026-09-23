import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Output quality for images placed into a PDF (requirements.md 3.8).
enum ImageQuality {
  high('High', 92),
  medium('Medium', 80),
  low('Small file', 62);

  const ImageQuality(this.label, this.jpegQuality);

  final String label;
  final int jpegQuality;
}

/// An image made ready to embed: re-encoded, upright, with known dimensions.
@immutable
class NormalizedImage {
  const NormalizedImage({
    required this.file,
    required this.width,
    required this.height,
  });

  final File file;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;
}

/// Prepares images for embedding.
///
/// Native on purpose: decoding happens outside Dart one image at a time, so 50
/// photos never become 50 bitmaps in memory (requirements.md 3.8).
abstract interface class ImageNormalizer {
  /// Re-encodes [source] as JPEG at [quality], applying the EXIF orientation
  /// so the result is upright, plus [quarterTurns] of extra rotation.
  Future<NormalizedImage> normalize(
    File source, {
    required File target,
    required ImageQuality quality,
    int quarterTurns = 0,
  });

  /// Converts already-rendered PNG bytes to JPEG (requirements.md 3.9).
  Future<Uint8List> toJpeg(Uint8List png, {int quality = 85});
}

class PlatformImageNormalizer implements ImageNormalizer {
  const PlatformImageNormalizer();

  @override
  Future<NormalizedImage> normalize(
    File source, {
    required File target,
    required ImageQuality quality,
    int quarterTurns = 0,
  }) async {
    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      target.path,
      quality: quality.jpegQuality,
      format: CompressFormat.jpeg,
      rotate: (quarterTurns % 4) * 90,
      // The plugin bakes the EXIF orientation into the pixels, which is the
      // only way a PDF viewer will show the image the right way up.
      autoCorrectionAngle: true,
      keepExif: false,
    );
    if (result == null) {
      throw const FileSystemException('could not read this image');
    }

    final size = await _sizeOf(File(result.path));
    return NormalizedImage(
      file: File(result.path),
      width: size.$1,
      height: size.$2,
    );
  }

  @override
  Future<Uint8List> toJpeg(Uint8List png, {int quality = 85}) =>
      FlutterImageCompress.compressWithList(
        png,
        quality: quality,
        format: CompressFormat.jpeg,
      );

  /// Reads the pixel dimensions from the JPEG header.
  ///
  /// Header-only: the pixels are never decoded in Dart, which is the whole
  /// point of doing this natively.
  static Future<(int, int)> _sizeOf(File jpeg) async {
    final bytes = await jpeg.readAsBytes();
    var offset = 2; // skip SOI
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      // SOF0..SOF15, excluding the non-frame markers DHT, JPG and DAC.
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        return (width, height);
      }
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 2 + length;
    }
    throw const FileSystemException('this image has no readable dimensions');
  }
}
