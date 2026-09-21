import 'package:flutter/foundation.dart';

import '../engine/pdf_failure.dart';
import 'cancel_token.dart';

enum JobStatus { idle, running, success, failure, cancelled }

@immutable
class JobProgress {
  const JobProgress({
    required this.completed,
    required this.total,
    required this.label,
  });

  final int completed;
  final int total;
  final String label;

  /// Null when the work has no countable steps, so the UI shows an
  /// indeterminate bar rather than a fake percentage (requirements.md 13).
  double? get fraction =>
      total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
}

/// Owns one long-running operation: its status, progress, cancellation and
/// failure mapping (requirements.md 13).
///
/// Features never touch [CancelToken] or catch engine errors themselves; they
/// hand a body to [run] and render whatever this exposes.
class JobController<T> extends ChangeNotifier {
  JobStatus _status = JobStatus.idle;
  JobProgress? _progress;
  PdfFailure? _failure;
  T? _result;
  CancelToken? _token;

  JobStatus get status => _status;
  JobProgress? get progress => _progress;
  PdfFailure? get failure => _failure;
  T? get result => _result;

  bool get isRunning => _status == JobStatus.running;

  Future<void> run(Future<T> Function(JobHandle handle) body) async {
    if (_status == JobStatus.running) return;

    final token = CancelToken();
    _token = token;
    _status = JobStatus.running;
    _progress = null;
    _failure = null;
    _result = null;
    notifyListeners();

    try {
      final value = await body(JobHandle._(token, _report));
      if (token.isCancelled) {
        _status = JobStatus.cancelled;
      } else {
        _result = value;
        _status = JobStatus.success;
      }
    } on PdfFailure catch (failure) {
      _failure = failure;
      _status = failure.kind == FailureKind.cancelled
          ? JobStatus.cancelled
          : JobStatus.failure;
    } catch (error, stack) {
      // Anything unmapped is a bug, not a user-facing condition. It still has
      // to land in the taxonomy rather than reaching the screen raw.
      debugPrint('Unmapped job error: $error\n$stack');
      _failure = PdfFailure(FailureKind.unknown, cause: error);
      _status = JobStatus.failure;
    } finally {
      _token = null;
      notifyListeners();
    }
  }

  void cancel() => _token?.cancel();

  void reset() {
    if (_status == JobStatus.running) return;
    _status = JobStatus.idle;
    _progress = null;
    _failure = null;
    _result = null;
    notifyListeners();
  }

  void _report(JobProgress progress) {
    if (_status != JobStatus.running) return;
    _progress = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }
}

/// Handed to a job body: how it reports progress and observes cancellation.
class JobHandle {
  JobHandle._(this.cancel, this._report);

  final CancelToken cancel;
  final void Function(JobProgress) _report;

  void report({
    required int completed,
    required int total,
    required String label,
  }) =>
      _report(JobProgress(completed: completed, total: total, label: label));
}
