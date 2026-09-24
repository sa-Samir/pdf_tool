import 'dart:io';

import 'package:flutter/foundation.dart';

import '../library/library_document.dart';
import 'document_store.dart';

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


/// Where a tool's result goes when nobody is asked (requirements.md 5.2).
///
/// Two conditions, both necessary:
///   - the app must own the document, because a picked file is only a copy of
///     the user's and writing to it would change nothing they can see;
///   - the tool must be changing that document rather than deriving a new one,
///     since Extract's whole point is to leave the original alone.
///
/// Editing your own document changes your own document -- which is what the
/// screen already said it would do, so there is nothing to ask. The previous
/// version is kept either way, which is what makes not asking safe.
SaveTarget defaultTargetFor(
  EditableSource source, {
  bool derivesNewDocument = false,
}) =>
    source.canReplace && !derivesNewDocument
        ? SaveTarget.replaceOriginal
        : SaveTarget.newFile;

/// The previous version of a document, and everything needed to put the world
/// back as it was (requirements.md 5.2).
///
/// Held only in memory, by the screen offering the undo. If the user never
/// takes it, the bytes it points at are removed by the launch prune.
@immutable
class ReplacedVersion {
  const ReplacedVersion({
    required this.replacement,
    required this.documentId,
    required this.documentName,
    required this.previousOperation,
    this.previousPageCount,
    this.refundToolId,
  });

  final Replacement replacement;

  /// The library entry to put back, along with the bytes.
  final String documentId;
  final String documentName;

  /// How the library described the document before this operation, so undoing
  /// restores the description and not only the content.
  final String previousOperation;
  final int? previousPageCount;

  /// A premium tool whose free run this operation spent, to be given back if
  /// the user undoes it. Null when nothing was charged.
  final String? refundToolId;
}

/// What a tool produced, and whether it can be taken back.
@immutable
class SaveOutcome {
  const SaveOutcome({required this.file, this.undo});

  final File file;

  /// Set only when an existing document was replaced. Null for a new file,
  /// which needs no undo: nothing was overwritten.
  final ReplacedVersion? undo;

  bool get replacedExisting => undo != null;
}
