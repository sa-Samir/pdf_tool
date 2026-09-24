import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/engine/compression.dart';
import '../../core/files/document_store.dart';
import '../../core/files/save_target.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';

/// A finished compression that has not been kept yet.
///
/// Unlike the other tools, compress does not commit its output straight away.
/// Requirements.md 3.7 requires showing the real before/after first and
/// offering to discard, so the result waits in its workspace until the user
/// decides. Exactly one of [keep] or [discard] must be called.
class CompressionOutcome {
  CompressionOutcome({
    required this.source,
    required this.file,
    required this.result,
    required this.level,
    required Workspace workspace,
  }) : _workspace = workspace;

  final EditableSource source;

  /// The compressed file, still in its workspace.
  final File file;

  final CompressionResult result;
  final CompressionLevel level;
  final Workspace _workspace;

  var _settled = false;

  /// Commits the result, records it in the library, and spends one free run.
  Future<SaveOutcome> keep(
    AppServices services, {
    SaveTarget target = SaveTarget.newFile,
  }) async {
    if (_settled) throw StateError('this outcome was already settled');
    _settled = true;
    try {
      final operation = 'Compressed · saved ${result.savedPercent}%';
      final document = source.document;
      // A result that did not shrink costs nothing (requirements.md 3.7).
      final charged = !result.isNoOp;
      final SaveOutcome outcome;

      if (target == SaveTarget.replaceOriginal && document != null) {
        final replacement =
            await services.store.replace(file, target: source.file);
        await services.library
            .refreshAfterReplace(document.id, operation: operation);
        outcome = SaveOutcome(
          file: replacement.file,
          undo: ReplacedVersion(
            replacement: replacement,
            documentId: document.id,
            documentName: document.name,
            // Captured before the refresh above overwrote them.
            previousOperation: document.operation,
            previousPageCount: document.pageCount,
            // Undoing this gives the run back: the user ends up with the
            // document they started with, so they were charged for nothing.
            refundToolId: charged ? 'compress' : null,
          ),
        );
      } else {
        final name =
            '${p.basenameWithoutExtension(source.file.path)} (compressed).pdf';
        final saved = await services.store.commit(file, desiredName: name);
        await services.library.record(
          file: saved,
          operation: operation,
          toolId: 'compress',
        );
        outcome = SaveOutcome(file: saved);
      }
      // Spent here rather than in the UI, because this is the one place that
      // means "the user kept it".
      if (charged) await services.entitlements.recordUse('compress');
      return outcome;
    } finally {
      await _workspace.dispose();
    }
  }

  /// Throws the result away. The original was never touched.
  Future<void> discard() async {
    if (_settled) return;
    _settled = true;
    await _workspace.dispose();
  }
}

/// Compresses [source], leaving the result for the user to accept or discard.
Future<CompressionOutcome> compressDocument({
  required AppServices services,
  required EditableSource source,
  required CompressionLevel level,
  required JobHandle handle,
}) async {
  final workspace = await services.store.openWorkspace();
  try {
    final temp = workspace.file('compressed.pdf');
    final result = await services.engine.compress(
      input: source.file,
      output: temp,
      level: level,
      cancel: handle.cancel,
      onStep: (completed, total) => handle.report(
        completed: completed,
        total: total,
        label: switch (completed) {
          1 => 'Reading the document...',
          2 => 'Re-encoding images...',
          _ => 'Writing the smaller PDF...',
        },
      ),
    );
    handle.cancel.throwIfCancelled();
    return CompressionOutcome(
      source: source,
      file: temp,
      result: result,
      level: level,
      workspace: workspace,
    );
  } catch (_) {
    // Only on the failure path: a successful outcome owns its workspace until
    // the user keeps or discards it.
    await workspace.dispose();
    rethrow;
  }
}
