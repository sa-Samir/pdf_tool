import 'package:path/path.dart' as p;

import '../../core/files/save_target.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/pages/page_edit_session.dart';
import '../../core/services/app_services.dart';

/// Saves a page-edit session (requirements.md 3.6).
///
/// One save for the whole session, whatever mix of reorder, rotate, delete and
/// duplicate it contains. Replacing an owned document hands back everything
/// needed to undo it.
Future<SaveOutcome> savePageEdits({
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

    final operation =
        suffix == 'extracted' ? 'Extracted pages' : 'Edited pages';
    final document = source.document;

    if (target == SaveTarget.replaceOriginal && document != null) {
      // Read before the swap: once the entry is refreshed, what it used to say
      // is gone, and undo has to restore the description as well as the bytes.
      final replacement = await services.store.replace(
        temp,
        target: source.file,
        expectedPages: pages.length,
      );
      await services.library.refreshAfterReplace(
        document.id,
        operation: operation,
        pageCount: pages.length,
      );
      return SaveOutcome(
        file: replacement.file,
        undo: ReplacedVersion(
          replacement: replacement,
          documentId: document.id,
          documentName: document.name,
          previousOperation: document.operation,
          previousPageCount: document.pageCount,
        ),
      );
    }

    final saved = await services.store.commit(
      temp,
      desiredName: '$stem ($suffix).pdf',
      expectedPages: pages.length,
    );
    await services.library.record(
      file: saved,
      operation: operation,
      toolId: 'reorder',
      pageCount: pages.length,
    );
    return SaveOutcome(file: saved);
  } finally {
    await workspace.dispose();
  }
}
