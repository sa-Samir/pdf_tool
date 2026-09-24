import '../../core/files/save_target.dart';
import '../../core/services/app_services.dart';

/// Puts back the document a tool replaced (requirements.md 5.2).
///
/// Plain Dart on purpose: this touches the filesystem, and a widget test runs
/// in a fake-async zone where real file I/O never completes. Keeping it out of
/// the widget layer is what makes both halves testable.
///
/// Restores three things, because restoring only the first would leave the
/// library describing a version that no longer exists:
///   1. the bytes,
///   2. the library entry's description and page count,
///   3. any free run the operation spent.
Future<void> undoReplace(AppServices services, ReplacedVersion version) async {
  await services.store.restore(version.replacement);
  await services.library.refreshAfterReplace(
    version.documentId,
    operation: version.previousOperation,
    pageCount: version.previousPageCount,
  );
  final refund = version.refundToolId;
  if (refund != null) await services.entitlements.refundUse(refund);
}
