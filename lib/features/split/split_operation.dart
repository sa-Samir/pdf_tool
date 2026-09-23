import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';
import '../../core/util/page_ranges.dart';

/// Writes one file per range. Lifted out of the widget for the same reason as
/// [mergeDocuments].
Future<List<File>> splitDocument({
  required AppServices services,
  required File source,
  required List<PageRange> ranges,
  required JobHandle handle,
}) async {
  final stem = p.basenameWithoutExtension(source.path);
  final workspace = await services.store.openWorkspace();
  try {
    final outputs = <File>[];
    for (var i = 0; i < ranges.length; i++) {
      handle.cancel.throwIfCancelled();
      handle.report(
        completed: i,
        total: ranges.length,
        label: 'Writing part ${i + 1} of ${ranges.length}...',
      );
      final range = ranges[i];
      final temp = workspace.file('part-$i.pdf');
      await services.engine.extractPages(
        input: source,
        output: temp,
        pageIndices: range.indices,
        cancel: handle.cancel,
      );
      final saved = await services.store.commit(
        temp,
        desiredName: '${stem}_$range.pdf',
        expectedPages: range.length,
      );
      await services.library.record(
        file: saved,
        operation: 'Split \u00b7 pages $range',
        toolId: 'split',
        pageCount: range.length,
      );
      outputs.add(saved);
    }
    handle.report(
      completed: ranges.length,
      total: ranges.length,
      label: 'Done',
    );
    return outputs;
  } finally {
    await workspace.dispose();
  }
}
