import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_toolbox/core/engine/pdf_engine.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/files/file_importer.dart';
import 'package:pdf_toolbox/core/jobs/cancel_token.dart';
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

  static Future<File> writeFake(File file, int pages) async {
    await file.parent.create(recursive: true);
    return file.writeAsString('PAGES:$pages');
  }

  @override
  Future<PdfDocumentInfo> inspect(File file, {String? password}) async {
    calls.add('inspect:${file.path}');
    if (failInspectWith case final failure?) throw failure;
    final text = await file.readAsString();
    final match = RegExp(r'^PAGES:(\d+)$').firstMatch(text.trim());
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
