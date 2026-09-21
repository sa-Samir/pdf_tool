import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';

/// The merge itself, lifted out of the widget so it can be tested as plain
/// Dart: ordering, progress, cancellation, verification and naming are the
/// parts worth testing, and none of them need a widget tree.
Future<File> mergeDocuments({
  required AppServices services,
  required List<File> inputs,
  required JobHandle handle,
  int? expectedPages,
}) async {
  final name = '${p.basenameWithoutExtension(inputs.first.path)} (merged).pdf';
  final workspace = await services.store.openWorkspace();
  try {
    final temp = workspace.file('merged.pdf');
    await services.engine.merge(
      inputs: inputs,
      output: temp,
      cancel: handle.cancel,
      onStep: (completed, total) => handle.report(
        completed: completed,
        total: total,
        label: completed >= total
            ? 'Writing the merged PDF...'
            : 'Merging file $completed of ${inputs.length}...',
      ),
    );
    handle.cancel.throwIfCancelled();
    return await services.store.commit(
      temp,
      desiredName: name,
      expectedPages: expectedPages,
    );
  } finally {
    // Requirements.md 5.2: nothing partial survives, however this ended.
    await workspace.dispose();
  }
}
