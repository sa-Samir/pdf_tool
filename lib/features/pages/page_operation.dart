import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/files/save_target.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/pages/page_edit_session.dart';
import '../../core/services/app_services.dart';

/// Saves a page-edit session as a new document (requirements.md 3.6).
///
/// One save for the whole session, whatever mix of reorder, rotate, delete and
/// duplicate it contains.
Future<File> savePageEdits({
  required AppServices services,
  required EditableSource source,
  required List<PageRef> pages,
  required JobHandle handle,
  SaveTarget target = SaveTarget.newFile,
  String suffix = 'edited',
}) async {
  final stem = p.basenameWithoutExtension(source.file.path);
  final workspace = await services.store.openWorkspace();
  try {
    final temp = workspace.file('edited.pdf');
    await services.engine.applyPageEdits(
      input: source.file,
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

    final document = source.document;
    if (target == SaveTarget.replaceOriginal && document != null) {
      final replaced = await services.store.replace(
        temp,
        target: source.file,
        expectedPages: pages.length,
      );
      await services.library.refreshAfterReplace(
        document.id,
        operation: suffix == 'extracted' ? 'Extracted pages' : 'Edited pages',
        pageCount: pages.length,
      );
      return replaced;
    }

    final saved = await services.store.commit(
      temp,
      desiredName: '$stem ($suffix).pdf',
      expectedPages: pages.length,
    );
    await services.library.record(
      file: saved,
      operation: suffix == 'extracted' ? 'Extracted pages' : 'Edited pages',
      toolId: 'reorder',
      pageCount: pages.length,
    );
    return saved;
  } finally {
    await workspace.dispose();
  }
}
