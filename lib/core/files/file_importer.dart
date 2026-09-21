import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../engine/pdf_failure.dart';
import 'document_store.dart';

/// Requirements.md 13: inputs above this are rejected with a clear message
/// rather than attempted and killed by the OS.
const int kMaxInputBytes = 200 * 1024 * 1024;

@immutable
class ImportedDocument {
  const ImportedDocument({
    required this.file,
    required this.displayName,
    required this.sizeBytes,
  });

  /// The sandbox copy. Never the picked URL.
  final File file;
  final String displayName;
  final int sizeBytes;
}

/// Brings files into the app.
abstract interface class FileImporter {
  /// Returns an empty list if the user cancels, which is not an error.
  Future<List<ImportedDocument>> pickPdfs({bool multiple = true});
}

/// The real one: the system document picker (requirements.md 3.3).
///
/// The picker needs no runtime permission on either platform, which is why the
/// app never asks for broad storage access.
class SystemFileImporter implements FileImporter {
  SystemFileImporter({required DocumentStore store}) : _store = store;

  final DocumentStore _store;

  @override
  Future<List<ImportedDocument>> pickPdfs({bool multiple = true}) async {
    final List<PlatformFile> picked;
    if (multiple) {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Choose PDFs',
      );
    } else {
      final one = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Choose a PDF',
      );
      picked = one == null ? const [] : [one];
    }

    final imported = <ImportedDocument>[];
    for (final file in picked) {
      final path = file.path;
      if (path == null) {
        // A provider handed back something with no local file (an undownloaded
        // cloud placeholder, typically). Requirements.md 3.3.
        throw const PdfFailure(
          FailureKind.io,
          detail: 'That file is not available on this device yet.',
        );
      }
      final size = await file.length() ?? 0;
      if (size > kMaxInputBytes) throw const PdfFailure(FailureKind.tooLarge);

      final copy = await _store.adoptImport(File(path), file.name);
      imported.add(ImportedDocument(
        file: copy,
        displayName: p.basename(copy.path),
        sizeBytes: size,
      ));
    }
    return imported;
  }
}
