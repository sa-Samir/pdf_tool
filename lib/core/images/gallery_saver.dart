import 'dart:io';

import 'package:gal/gal.dart';

/// Result of trying to put images in the device's photo library.
enum GallerySaveOutcome { saved, denied, failed }

/// Saves exported images to the photo library (requirements.md 3.9).
abstract interface class GallerySaver {
  /// Whether saving is possible on this device at all.
  bool get isSupported;

  Future<GallerySaveOutcome> save(List<File> images, {String? album});
}

class PlatformGallerySaver implements GallerySaver {
  const PlatformGallerySaver();

  /// Only the mobile platforms have a photo library worth writing to.
  @override
  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  @override
  Future<GallerySaveOutcome> save(List<File> images, {String? album}) async {
    if (!isSupported || images.isEmpty) return GallerySaveOutcome.failed;
    try {
      if (!await Gal.hasAccess(toAlbum: album != null)) {
        if (!await Gal.requestAccess(toAlbum: album != null)) {
          return GallerySaveOutcome.denied;
        }
      }
      for (final image in images) {
        await Gal.putImage(image.path, album: album);
      }
      return GallerySaveOutcome.saved;
    } on GalException catch (e) {
      return e.type == GalExceptionType.accessDenied
          ? GallerySaveOutcome.denied
          : GallerySaveOutcome.failed;
    }
  }
}
