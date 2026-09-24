import 'dart:io';

import 'package:flutter/foundation.dart';

import '../library/library_document.dart';

/// Where a tool's result should go (requirements.md 5.2).
enum SaveTarget {
  /// Keep the original and add the result beside it.
  newFile,

  /// Put the result in the original's place.
  replaceOriginal,
}

/// The document a tool is working on, and whether it can be written back to.
///
/// The distinction matters and is not cosmetic. A file picked through the
/// system picker is copied into the sandbox first (requirements.md 3.3): the
/// user's own file lives outside, we hold no write permission on it, and on
/// iOS the picked URL has already expired. Offering to "replace" it would
/// quietly overwrite our copy and leave their file untouched -- so that choice
/// is offered only for documents the app itself owns.
@immutable
class EditableSource {
  const EditableSource({
    required this.file,
    required this.displayName,
    this.document,
  });

  /// A document the app owns, straight from the library.
  factory EditableSource.owned(LibraryDocument document, File file) =>
      EditableSource(
        file: file,
        displayName: document.name,
        document: document,
      );

  /// A copy of a file the user picked from outside the app.
  const EditableSource.imported({
    required File file,
    required String displayName,
  }) : this(file: file, displayName: displayName);

  final File file;
  final String displayName;

  /// Set when this came from the library, which is the only case where the
  /// app can honestly write back.
  final LibraryDocument? document;

  bool get canReplace => document != null;
}
