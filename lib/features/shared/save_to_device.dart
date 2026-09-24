import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/files/device_exporter.dart';
import '../../core/services/app_services.dart';

/// Copies [files] out to a place the user picks, and says what happened
/// (requirements.md 6).
///
/// A copy, never a move: the library keeps its own file, so a document that has
/// been saved out is still here to work on afterwards.
///
/// Needs a Scaffold above [context] for the report.
Future<DeviceSaveResult> saveToDevice(
  BuildContext context,
  List<File> files,
) async {
  final services = AppServicesScope.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final result = await services.deviceExport.save(files);
  final message = describeDeviceSave(result, files);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
  return result;
}

/// What to tell the user, or null when the honest answer is nothing.
///
/// Separated from the widget so it can be tested directly: the wording is the
/// feature here, and a partial save must not be reported as a whole one.
String? describeDeviceSave(DeviceSaveResult result, List<File> files) {
  final asked = files.length;
  final where = result.location == null ? '' : ' to ${result.location}';

  return switch (result.status) {
    // Backing out of the picker is a choice, not an event worth announcing.
    DeviceSaveStatus.cancelled => null,
    DeviceSaveStatus.unsupported =>
      'Saving to this device is not supported here.',
    DeviceSaveStatus.failed => asked == 1
        ? 'Could not save ${p.basename(files.single.path)}.'
        : 'Could not save those $asked files.',
    DeviceSaveStatus.saved when result.savedCount < asked =>
      // Say so rather than rounding a partial result up to success.
      'Saved ${result.savedCount} of $asked files$where.',
    DeviceSaveStatus.saved => asked == 1
        ? 'Saved ${p.basename(files.single.path)}$where.'
        : 'Saved $asked files$where.',
  };
}
