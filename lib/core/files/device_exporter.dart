import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What came of saving files out to the device (requirements.md 6).
enum DeviceSaveStatus {
  saved,

  /// The user backed out of the system picker. Not an error, and never
  /// reported as one.
  cancelled,

  failed,

  /// No system document picker on this platform.
  unsupported,
}

@immutable
class DeviceSaveResult {
  const DeviceSaveResult(this.status, {this.savedCount = 0, this.location});

  const DeviceSaveResult.cancelled() : this(DeviceSaveStatus.cancelled);

  final DeviceSaveStatus status;

  /// How many files actually landed. Can be short of what was asked for when
  /// one of several fails, so the message can be honest about it.
  final int savedCount;

  /// Where they went, when the platform tells us in words worth showing.
  final String? location;

  bool get isSaved => status == DeviceSaveStatus.saved;
}

/// Copies finished documents out of the app, to wherever the user chooses
/// (requirements.md 6).
///
/// This is the answer to a problem that is otherwise invisible: everything the
/// app produces lives in app-private storage, so it is **deleted when the app
/// is uninstalled**. The share sheet could always rescue a file, but nobody
/// reads "share" as "keep this".
///
/// Always a copy, never a move. The library keeps its own file, so a document
/// that has been saved out is still here to work on.
abstract interface class DeviceExporter {
  bool get isSupported;

  Future<DeviceSaveResult> save(List<File> files);
}

/// Talks to a small amount of native code on each platform.
///
/// Deliberately not `file_picker`'s `saveFile()`, whose `bytes` parameter is
/// required: that would mean holding an entire document in memory, and
/// requirements.md 13 caps input at 200 MB, peak RSS at 400 MB, and states that
/// large documents are streamed rather than materialised. A 200 MB list plus
/// the copy a platform channel makes crossing into Kotlin or Swift would breach
/// that on exactly the files most worth rescuing. Both native sides take a path
/// and stream it instead.
class PlatformDeviceExporter implements DeviceExporter {
  const PlatformDeviceExporter();

  static const _channel =
      MethodChannel('com.samir.pdf_toolbox/device_export');

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<DeviceSaveResult> save(List<File> files) async {
    if (!isSupported) return const DeviceSaveResult(DeviceSaveStatus.unsupported);
    if (files.isEmpty) return const DeviceSaveResult.cancelled();

    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'save',
        {'paths': [for (final file in files) file.path]},
      );
      if (reply == null) return const DeviceSaveResult(DeviceSaveStatus.failed);

      final status = switch (reply['status'] as String?) {
        'saved' => DeviceSaveStatus.saved,
        'cancelled' => DeviceSaveStatus.cancelled,
        _ => DeviceSaveStatus.failed,
      };
      return DeviceSaveResult(
        status,
        savedCount: (reply['count'] as int?) ?? 0,
        location: reply['location'] as String?,
      );
    } on PlatformException {
      // Nothing was moved or deleted, so there is nothing to undo -- only
      // something to tell the user.
      return const DeviceSaveResult(DeviceSaveStatus.failed);
    } on MissingPluginException {
      return const DeviceSaveResult(DeviceSaveStatus.unsupported);
    }
  }
}
