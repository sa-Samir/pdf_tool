import 'recent_document.dart';

/// Source of the recent-files list (requirements.md 4).
abstract interface class RecentsRepository {
  Future<List<RecentDocument>> load();
}

/// Phase 1 stub: there is no file store yet, so history is always empty.
///
/// It is asynchronous on purpose. Requirements.md 3.1 requires the home screen
/// to render and be interactive before any file-system or database work
/// completes, and building against a synchronous stub would hide a violation of
/// that until the real store arrives in Phase 2 (roadmap.md 6).
class EmptyRecentsRepository implements RecentsRepository {
  const EmptyRecentsRepository();

  @override
  Future<List<RecentDocument>> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return const <RecentDocument>[];
  }
}
