import 'package:flutter/foundation.dart';

/// A document the app produced and still owns (requirements.md 4).
@immutable
class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.sizeBytes,
    required this.pageCount,
    required this.operation,
    required this.toolId,
    required this.createdAt,
    this.favorite = false,
    this.folderId,
  });

  final String id;
  final String name;

  /// Path relative to the app's documents directory -- never absolute.
  ///
  /// iOS gives the app container a new UUID on reinstall and can change it on
  /// update, so an absolute path stored today can be dead tomorrow. The
  /// relative path outlives that.
  final String relativePath;

  final int sizeBytes;

  /// Null when the page count was not known at save time.
  final int? pageCount;

  /// What produced it, in the user's words: "Merged", "Split", "Compressed".
  final String operation;

  /// Which tool, so "do this again" can reopen the right screen.
  final String toolId;

  final DateTime createdAt;
  final bool favorite;

  /// Null when the document sits outside any folder.
  final String? folderId;

  LibraryDocument copyWith({
    String? name,
    String? relativePath,
    int? sizeBytes,
    bool? favorite,
    String? folderId,
    bool clearFolder = false,
  }) =>
      LibraryDocument(
        id: id,
        name: name ?? this.name,
        relativePath: relativePath ?? this.relativePath,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        pageCount: pageCount,
        operation: operation,
        toolId: toolId,
        createdAt: createdAt,
        favorite: favorite ?? this.favorite,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'relative_path': relativePath,
        'size_bytes': sizeBytes,
        'page_count': pageCount,
        'operation': operation,
        'tool_id': toolId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'favorite': favorite ? 1 : 0,
        'folder_id': folderId,
      };

  static LibraryDocument fromRow(Map<String, Object?> row) => LibraryDocument(
        id: row['id']! as String,
        name: row['name']! as String,
        relativePath: row['relative_path']! as String,
        sizeBytes: row['size_bytes']! as int,
        pageCount: row['page_count'] as int?,
        operation: row['operation']! as String,
        toolId: row['tool_id']! as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
        favorite: (row['favorite']! as int) == 1,
        folderId: row['folder_id'] as String?,
      );
}

/// How the library list is ordered (requirements.md 5.1).
enum LibrarySort { newest, name, size }

/// A folder the user made to organise their documents (requirements.md 5.1).
@immutable
class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.documentCount = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// How many documents are filed here. Populated when listing.
  final int documentCount;

  LibraryFolder copyWith({String? name, int? documentCount}) => LibraryFolder(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        documentCount: documentCount ?? this.documentCount,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static LibraryFolder fromRow(Map<String, Object?> row, {int count = 0}) =>
      LibraryFolder(
        id: row['id']! as String,
        name: row['name']! as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
        documentCount: count,
      );
}

/// Which documents a listing should include (requirements.md 5.1).
sealed class FolderScope {
  const FolderScope();

  /// Everything, wherever it is filed.
  static const everywhere = FolderScopeEverywhere();

  /// Only documents not in any folder.
  static const root = FolderScopeRoot();

  /// Only documents in one folder.
  const factory FolderScope.inside(String folderId) = FolderScopeInside;
}

class FolderScopeEverywhere extends FolderScope {
  const FolderScopeEverywhere();
}

class FolderScopeRoot extends FolderScope {
  const FolderScopeRoot();
}

class FolderScopeInside extends FolderScope {
  const FolderScopeInside(this.folderId);
  final String folderId;
}
