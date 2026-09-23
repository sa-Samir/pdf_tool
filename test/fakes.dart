import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_toolbox/core/engine/compression.dart';
import 'package:pdf_toolbox/core/engine/pdf_engine.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/file_importer.dart';
import 'package:pdf_toolbox/core/jobs/cancel_token.dart';
import 'package:pdf_toolbox/core/library/library_document.dart';
import 'package:pdf_toolbox/core/library/library_repository.dart';
import 'package:pdf_toolbox/core/pages/page_edit_session.dart';

/// A stand-in engine backed by tiny text files of the form `PAGES:n`.
///
/// Real files on a real filesystem, so DocumentStore's verify-then-commit path
/// is exercised for real; only the PDF parsing is faked.

/// A real 1x1 transparent PNG. Widget tests decode this for real, so an
/// invalid stand-in would fail in the image pipeline rather than in the test.
final kTinyPng = Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 218, 99, 96, 0, 2, 0, 0, 5, 0, 1, 233, 250, 220, 216, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

class FakePdfEngine implements PdfEngine {
  FakePdfEngine();

  /// Set to make merge/extract fail, for error-path tests.
  PdfFailure? failWith;

  /// Set to make [inspect] fail.
  PdfFailure? failInspectWith;

  /// Blocks merge/extract until completed, so cancellation can be observed.
  Completer<void>? gate;

  final calls = <String>[];
  var disposed = false;

  /// Writes a stand-in document. [padTo] inflates it to a given size so tests
  /// can express meaningful ratios; the marker stays on the first line.
  static Future<File> writeFake(File file, int pages, {int padTo = 0}) async {
    await file.parent.create(recursive: true);
    final marker = 'PAGES:$pages\n';
    final padding = padTo > marker.length ? padTo - marker.length : 0;
    return file.writeAsString(marker + ('.' * padding));
  }

  @override
  Future<PdfDocumentInfo> inspect(File file, {String? password}) async {
    calls.add('inspect:${file.path}');
    if (failInspectWith case final failure?) throw failure;
    final text = await file.readAsString();
    // The marker is the first line; anything after it is padding.
    final firstLine = text.split('\n').first.trim();
    final match = RegExp(r'^PAGES:(\d+)$').firstMatch(firstLine);
    if (match == null) throw const PdfFailure(FailureKind.corruptFile);
    return PdfDocumentInfo(
      pageCount: int.parse(match.group(1)!),
      sizeBytes: await file.length(),
    );
  }

  @override
  Future<void> merge({
    required List<File> inputs,
    required File output,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  }) async {
    calls.add('merge:${inputs.length}');
    final total = inputs.length + 1;
    var pages = 0;
    for (var i = 0; i < inputs.length; i++) {
      cancel?.throwIfCancelled();
      await _waitGate(cancel);
      pages += (await inspect(inputs[i])).pageCount;
      onStep?.call(i + 1, total);
    }
    if (failWith case final failure?) throw failure;
    cancel?.throwIfCancelled();
    await writeFake(output, pages);
    onStep?.call(total, total);
  }

  @override
  Future<void> extractPages({
    required File input,
    required File output,
    required List<int> pageIndices,
    CancelToken? cancel,
    String? password,
  }) async {
    calls.add('extract:${pageIndices.length}');
    cancel?.throwIfCancelled();
    await _waitGate(cancel);
    if (failWith case final failure?) throw failure;
    cancel?.throwIfCancelled();
    await writeFake(output, pageIndices.length);
  }

  @override
  Future<Uint8List> renderPage({
    required File input,
    required int pageIndex,
    required int maxSize,
    CancelToken? cancel,
    String? password,
  }) async {
    calls.add('render:$pageIndex');
    final pages = (await inspect(input)).pageCount;
    if (pageIndex < 0 || pageIndex >= pages) {
      throw const PdfFailure(FailureKind.pageOutOfRange);
    }
    return kTinyPng;
  }

  @override
  Future<void> applyPageEdits({
    required File input,
    required File output,
    required List<PageRef> pages,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  }) async {
    calls.add('applyPageEdits:${pages.length}');
    cancel?.throwIfCancelled();
    await _waitGate(cancel);
    if (failWith case final failure?) throw failure;
    cancel?.throwIfCancelled();
    onStep?.call(1, 2);
    await writeFake(output, pages.length);
    onStep?.call(2, 2);
  }

  /// What [compress] should pretend to achieve, as a fraction of the input.
  double compressionRatio = 0.25;

  /// Raster images the fake claims to find, driving the outlook.
  int imageCount = 4;

  @override
  Future<CompressionOutlook> inspectForCompression(
    File input, {
    CancelToken? cancel,
    String? password,
  }) async {
    calls.add('inspectForCompression');
    final info = await inspect(input);
    return CompressionOutlook(
      sizeBytes: info.sizeBytes,
      pageCount: info.pageCount,
      imageCount: imageCount,
      pagesWithImages: imageCount == 0 ? 0 : info.pageCount,
    );
  }

  @override
  Future<CompressionResult> compress({
    required File input,
    required File output,
    required CompressionLevel level,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  }) async {
    calls.add('compress:${level.name}');
    cancel?.throwIfCancelled();
    await _waitGate(cancel);
    if (failWith case final failure?) throw failure;
    cancel?.throwIfCancelled();

    final original = await inspect(input);
    onStep?.call(1, 2);
    await writeFake(
      output,
      original.pageCount,
      padTo: (original.sizeBytes * compressionRatio).round(),
    );
    onStep?.call(2, 2);

    return CompressionResult(
      originalBytes: original.sizeBytes,
      compressedBytes: await output.length(),
    );
  }

  @override
  Future<void> dispose() async => disposed = true;

  Future<void> _waitGate(CancelToken? cancel) async {
    final g = gate;
    if (g == null) return;
    await g.future;
    cancel?.throwIfCancelled();
  }
}

class FakeFileImporter implements FileImporter {
  FakeFileImporter(this.queued);

  /// Returned in order, one list per pick.
  final List<List<ImportedDocument>> queued;
  var pickCount = 0;
  PdfFailure? failWith;

  @override
  Future<List<ImportedDocument>> pickPdfs({bool multiple = true}) async {
    pickCount++;
    if (failWith case final failure?) throw failure;
    if (queued.isEmpty) return const [];
    return queued.removeAt(0);
  }
}

Future<ImportedDocument> fakeDocument(
  Directory dir,
  String name,
  int pages,
) async {
  final file = await FakePdfEngine.writeFake(File('${dir.path}/$name'), pages);
  return ImportedDocument(
    file: file,
    displayName: name,
    sizeBytes: await file.length(),
  );
}

/// Engine for widget tests: page counts come from a map, nothing touches the
/// filesystem. Widget tests run in a fake-async zone where real I/O never
/// completes, so anything that reads a file would hang the test rather than
/// fail it.
class MemoryFakeEngine implements PdfEngine {
  MemoryFakeEngine(this.pages);

  final Map<String, int> pages;

  /// How many renders were asked for -- lets a test prove the cache works.
  var renderCount = 0;

  @override
  Future<PdfDocumentInfo> inspect(File file, {String? password}) async {
    final count = pages[file.path];
    if (count == null) throw const PdfFailure(FailureKind.corruptFile);
    return PdfDocumentInfo(pageCount: count, sizeBytes: 1024);
  }

  @override
  Future<void> merge({
    required List<File> inputs,
    required File output,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  }) async =>
      throw UnimplementedError('widget tests do not run operations');

  @override
  Future<void> extractPages({
    required File input,
    required File output,
    required List<int> pageIndices,
    CancelToken? cancel,
    String? password,
  }) async =>
      throw UnimplementedError('widget tests do not run operations');

  @override
  Future<Uint8List> renderPage({
    required File input,
    required int pageIndex,
    required int maxSize,
    CancelToken? cancel,
    String? password,
  }) async {
    renderCount++;
    final count = pages[input.path];
    if (count == null || pageIndex < 0 || pageIndex >= count) {
      throw const PdfFailure(FailureKind.pageOutOfRange);
    }
    return kTinyPng;
  }

  @override
  Future<void> applyPageEdits({
    required List<PageRef> pages,
    required File input,
    required File output,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  }) async =>
      throw UnimplementedError('widget tests do not run operations');

  /// What [inspectForCompression] reports. Widget tests drive the copy from
  /// this without touching a file.
  CompressionOutlook outlook = const CompressionOutlook(
    sizeBytes: 9400000,
    pageCount: 12,
    imageCount: 12,
    pagesWithImages: 12,
  );

  @override
  Future<CompressionOutlook> inspectForCompression(
    File input, {
    CancelToken? cancel,
    String? password,
  }) async =>
      outlook;

  @override
  Future<CompressionResult> compress({
    required File input,
    required File output,
    required CompressionLevel level,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  }) async =>
      throw UnimplementedError('widget tests do not run operations');

  @override
  Future<void> dispose() async {}
}

/// An [ImportedDocument] that refers to a path without creating anything.
ImportedDocument memoryDocument(String name, {int sizeBytes = 1024}) =>
    ImportedDocument(
      file: File('/memory/$name'),
      displayName: name,
      sizeBytes: sizeBytes,
    );

/// In-memory library for widget tests: no database, no filesystem.
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository([List<LibraryDocument>? initial])
      : _documents = [...?initial];

  final List<LibraryDocument> _documents;
  var pruneCount = 0;
  var clearCount = 0;

  /// Set to make [fileFor] report the file as gone.
  var filesMissing = false;

  /// Delays [list], so a test can observe the screen while recents load.
  Duration listDelay = Duration.zero;

  List<LibraryDocument> get documents => List.unmodifiable(_documents);

  @override
  Future<List<LibraryDocument>> list({
    LibrarySort sort = LibrarySort.newest,
    String query = '',
    bool favouritesOnly = false,
    int limit = 0,
  }) async {
    if (listDelay > Duration.zero) await Future<void>.delayed(listDelay);
    var result = _documents.where((d) {
      if (favouritesOnly && !d.favorite) return false;
      if (query.trim().isEmpty) return true;
      return d.name.toLowerCase().contains(query.trim().toLowerCase());
    }).toList();

    result.sort(switch (sort) {
      LibrarySort.newest => (a, b) => b.createdAt.compareTo(a.createdAt),
      LibrarySort.name =>
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      LibrarySort.size => (a, b) => b.sizeBytes.compareTo(a.sizeBytes),
    });
    if (limit > 0 && result.length > limit) {
      result = result.sublist(0, limit);
    }
    return result;
  }

  @override
  Future<LibraryDocument?> byId(String id) async =>
      _documents.where((d) => d.id == id).firstOrNull;

  @override
  Future<LibraryDocument> record({
    required File file,
    required String operation,
    required String toolId,
    int? pageCount,
  }) async {
    final document = LibraryDocument(
      id: '${_documents.length}-$operation',
      name: file.path.split('/').last,
      relativePath: file.path.split('/').last,
      sizeBytes: 1024,
      pageCount: pageCount,
      operation: operation,
      toolId: toolId,
      createdAt: DateTime.now(),
    );
    _documents.insert(0, document);
    return document;
  }

  @override
  Future<LibraryDocument> rename(String id, String name) async {
    final index = _documents.indexWhere((d) => d.id == id);
    final renamed = _documents[index].copyWith(name: name);
    _documents[index] = renamed;
    return renamed;
  }

  @override
  Future<void> setFavorite(String id, bool favorite) async {
    final index = _documents.indexWhere((d) => d.id == id);
    _documents[index] = _documents[index].copyWith(favorite: favorite);
  }

  @override
  Future<void> delete(String id, {bool deleteFile = true}) async {
    _documents.removeWhere((d) => d.id == id);
  }

  @override
  Future<File?> fileFor(LibraryDocument document) async =>
      filesMissing ? null : File('/memory/${document.relativePath}');

  @override
  Future<int> pruneMissing() async {
    pruneCount++;
    return 0;
  }

  @override
  Future<void> clearAll() async {
    clearCount++;
    _documents.clear();
  }
}

LibraryDocument fakeLibraryDocument(
  String name, {
  String operation = 'Merged',
  int sizeBytes = 1024,
  int? pageCount = 4,
  bool favorite = false,
  DateTime? createdAt,
}) =>
    LibraryDocument(
      id: name,
      name: name,
      relativePath: name,
      sizeBytes: sizeBytes,
      pageCount: pageCount,
      operation: operation,
      toolId: 'merge',
      createdAt: createdAt ?? DateTime(2026, 9, 23, 10, 0),
      favorite: favorite,
    );
