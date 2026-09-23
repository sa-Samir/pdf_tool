import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/jobs/job_controller.dart';
import '../../core/pages/page_edit_session.dart';
import '../../core/services/app_services.dart';

/// Saves a page-edit session as a new document (requirements.md 3.6).
///
/// One save for the whole session, whatever mix of reorder, rotate, delete and
/// duplicate it contains.
Future<File> savePageEdits({
  required AppServices services,
  required File source,
  required List<PageRef> pages,
  required JobHandle handle,
  String suffix = 'edited',
}) async {
  final stem = p.basenameWithoutExtension(source.path);
  final workspace = await services.store.openWorkspace();
  try {
    final temp = workspace.file('edited.pdf');
    await services.engine.applyPageEdits(
      input: source,
      output: temp,
      pages: pages,
      cancel: handle.cancel,
      onStep: (completed, total) => handle.report(
        completed: completed,
        total: total,
        label: 'Saving ${pages.length} page'
            '${pages.length == 1 ? '' : 's'}...',
      ),
    );
    handle.cancel.throwIfCancelled();
    return await services.store.commit(
      temp,
      desiredName: '$stem ($suffix).pdf',
      expectedPages: pages.length,
    );
  } finally {
    await workspace.dispose();
  }
}
