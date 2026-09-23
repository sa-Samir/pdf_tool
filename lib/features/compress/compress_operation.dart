import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/engine/compression.dart';
import '../../core/files/document_store.dart';
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

  final File source;

  /// The compressed file, still in its workspace.
  final File file;

  final CompressionResult result;
  final CompressionLevel level;
  final Workspace _workspace;

  var _settled = false;

  /// Commits the result and records it in the library.
  Future<File> keep(AppServices services) async {
    if (_settled) throw StateError('this outcome was already settled');
    _settled = true;
    try {
      final name = '${p.basenameWithoutExtension(source.path)} (compressed).pdf';
      final saved = await services.store.commit(file, desiredName: name);
      await services.library.record(
        file: saved,
        operation: 'Compressed · saved ${result.savedPercent}%',
        toolId: 'compress',
      );
      return saved;
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
  required File source,
  required CompressionLevel level,
  required JobHandle handle,
}) async {
  final workspace = await services.store.openWorkspace();
  try {
    final temp = workspace.file('compressed.pdf');
    final result = await services.engine.compress(
      input: source,
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
