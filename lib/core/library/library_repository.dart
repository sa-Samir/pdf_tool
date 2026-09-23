import 'dart:io';

import 'library_document.dart';

/// Retention defaults from requirements.md 4.
class RetentionPolicy {
  const RetentionPolicy({this.maxEntries = 50, this.maxAge = const Duration(days: 30)});

  final int maxEntries;
  final Duration maxAge;

  static const keepEverything =
      RetentionPolicy(maxEntries: 1 << 30, maxAge: Duration(days: 36500));
}

/// The app's own record of what it has produced (requirements.md 4, 5).
abstract interface class LibraryRepository {
  /// Newest first. [limit] of 0 means no limit.
  Future<List<LibraryDocument>> list({
    LibrarySort sort = LibrarySort.newest,
    String query = '',
    bool favouritesOnly = false,
    int limit = 0,
  });

  Future<LibraryDocument?> byId(String id);

  /// Records a file the app just wrote, and applies the retention policy.
  Future<LibraryDocument> record({
    required File file,
    required String operation,
    required String toolId,
    int? pageCount,
  });

  Future<LibraryDocument> rename(String id, String name);

  Future<void> setFavorite(String id, bool favorite);

  /// Removes the entry and, unless told otherwise, the file it points at.
  Future<void> delete(String id, {bool deleteFile = true});

  /// Resolves an entry to a file on disk, or null if it has gone missing.
  Future<File?> fileFor(LibraryDocument document);

  /// Drops entries whose file no longer exists (requirements.md 4).
  Future<int> pruneMissing();

  /// Forgets everything and deletes the files (Settings, requirements.md 11).
  Future<void> clearAll();
}
