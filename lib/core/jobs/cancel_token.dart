import '../engine/pdf_failure.dart';

/// Cooperative cancellation, passed down into the engine.
///
/// Requirements.md 13: every operation expected to exceed 2s is cancellable,
/// and the cancel takes effect in under a second.
class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Runs [listener] on cancellation, or immediately if already cancelled.
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void throwIfCancelled() {
    if (_cancelled) throw const PdfFailure(FailureKind.cancelled);
  }
}
