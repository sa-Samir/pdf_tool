import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' as px;

import '../jobs/cancel_token.dart';
import '../pages/page_edit_session.dart';
import 'pdf_engine.dart';
import 'pdf_failure.dart';

/// The only file in the app that imports the PDF package (requirements.md 17).
///
/// Its whole job is to translate: our value types in, engine calls out, engine
/// errors mapped onto the requirements.md 12 taxonomy on the way back.
class PdfManipulatorEngine implements PdfEngine {
  PdfManipulatorEngine() : _pdf = px.Pdf();

  final px.Pdf _pdf;

  @override
  Future<PdfDocumentInfo> inspect(File file, {String? password}) async {
    final size = await _sizeOf(file);
    final doc = await _guard(
      () => _pdf.open(FileSource(file), password: password),
    );
    try {
      return PdfDocumentInfo(pageCount: doc.pageCount, sizeBytes: size);
    } finally {
      await doc.dispose();
    }
  }

  @override
  Future<void> merge({
    required List<File> inputs,
    required File output,
    void Function(int completed, int total)? onStep,
    CancelToken? cancel,
    String? password,
  }) async {
    if (inputs.isEmpty) {
      throw const PdfFailure(FailureKind.unknown, detail: 'no inputs');
    }

    // Driven step by step rather than through the package's one-shot merge, so
    // the UI gets real per-file progress instead of a spinner.
    final total = inputs.length + 1; // inputs, then the write
    final editor = await _guard(
      () => _pdf.edit(FileSource(inputs.first), password: password),
      cancel,
    );
    try {
      onStep?.call(1, total);
      for (var i = 1; i < inputs.length; i++) {
        cancel?.throwIfCancelled();
        await _guard(
          () => editor.mergeFrom(FileSource(inputs[i])),
          cancel,
        );
        onStep?.call(i + 1, total);
      }
      cancel?.throwIfCancelled();
      final sink = await FileSink.create(output);
      await _guard(() => editor.save(sink), cancel);
      onStep?.call(total, total);
    } finally {
      await editor.dispose();
    }
  }

  @override
  Future<void> extractPages({
    required File input,
    required File output,
    required List<int> pageIndices,
    CancelToken? cancel,
    String? password,
  }) async {
    if (pageIndices.isEmpty) {
      throw const PdfFailure(FailureKind.unknown, detail: 'no pages');
    }
    cancel?.throwIfCancelled();
    final sink = await FileSink.create(output);
    await _guard(
      () => _pdf.extractPages(
        FileSource(input),
        sink,
        pages: pageIndices,
        password: password,
      ),
      cancel,
    );
  }

  @override
  Future<Uint8List> renderPage({
    required File input,
    required int pageIndex,
    required int maxSize,
    CancelToken? cancel,
    String? password,
  }) async {
    final doc = await _guard(
      () => _pdf.open(FileSource(input), password: password),
      cancel,
    );
    try {
      cancel?.throwIfCancelled();
      final stream = doc.render(
        pages: px.PdfPages.single(pageIndex),
        size: px.PdfRenderSize.thumbnail(maxSize),
      );
      try {
        final page = await stream.first;
        return page.data;
      } on px.PdfError catch (e) {
        throw _map(e);
      } on StateError catch (e) {
        // The stream ended without yielding: the page does not exist.
        throw PdfFailure(FailureKind.pageOutOfRange, cause: e);
      }
    } finally {
      await doc.dispose();
    }
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
    if (pages.isEmpty) {
      throw const PdfFailure(FailureKind.unknown, detail: 'no pages');
    }

    // How the engine actually behaves, established by probing it:
    //
    //  * selectPages reorders and drops, but rejects a repeated index.
    //  * mergeFrom appends in the order given, including repeats.
    //  * nothing else works on a document that has had mergeFrom applied --
    //    it must be saved and reopened first.
    //
    // So: plain reorder/delete/rotate is one pass. Duplicated pages need the
    // copies appended, written out, and reopened before the final ordering.
    final seen = <int, int>{};
    final appended = <int>[]; // source indices to append, in append order
    final wanted = <int>[]; // indices into the pass-1 document, in final order
    var originalCount = 0;

    final probe = await _guard(
      () => _pdf.edit(FileSource(input), password: password),
      cancel,
    );
    try {
      originalCount = await _guard(() => probe.pageCount, cancel);
    } finally {
      await probe.dispose();
    }

    for (final page in pages) {
      final count = seen[page.sourceIndex] ?? 0;
      seen[page.sourceIndex] = count + 1;
      if (count == 0) {
        wanted.add(page.sourceIndex);
      } else {
        wanted.add(originalCount + appended.length);
        appended.add(page.sourceIndex);
      }
    }

    final totalSteps = appended.isEmpty ? 2 : 3;
    var step = 0;

    File source = input;
    File? intermediate;
    try {
      if (appended.isNotEmpty) {
        intermediate = File('${output.path}.pass1');
        final editor = await _guard(
          () => _pdf.edit(FileSource(input), password: password),
          cancel,
        );
        try {
          for (final sourceIndex in appended) {
            cancel?.throwIfCancelled();
            await _guard(
              () => editor.mergeFrom(FileSource(input), pages: [sourceIndex]),
              cancel,
            );
          }
          cancel?.throwIfCancelled();
          final sink = await FileSink.create(intermediate);
          await _guard(() => editor.save(sink), cancel);
        } finally {
          await editor.dispose();
        }
        source = intermediate;
        onStep?.call(++step, totalSteps);
      }

      final editor = await _guard(
        () => _pdf.edit(
          FileSource(source),
          password: source == input ? password : null,
        ),
        cancel,
      );
      try {
        cancel?.throwIfCancelled();
        await _guard(() => editor.selectPages(wanted), cancel);
        onStep?.call(++step, totalSteps);

        for (var i = 0; i < pages.length; i++) {
          final rotation = pages[i].rotation;
          if (rotation == 0) continue;
          cancel?.throwIfCancelled();
          await _guard(() => editor.rotatePage(i, degrees: rotation), cancel);
        }

        cancel?.throwIfCancelled();
        final sink = await FileSink.create(output);
        await _guard(() => editor.save(sink), cancel);
        onStep?.call(totalSteps, totalSteps);
      } finally {
        await editor.dispose();
      }
    } finally {
      if (intermediate != null) {
        try {
          if (await intermediate.exists()) await intermediate.delete();
        } on FileSystemException {
          // The workspace sweep will get it.
        }
      }
    }
  }

  @override
  Future<void> dispose() => _pdf.dispose();

  Future<int> _sizeOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException catch (e) {
      throw PdfFailure(FailureKind.io, cause: e);
    }
  }

  /// Runs an engine task, wiring [cancel] to it and mapping its errors.
  Future<T> _guard<T>(px.PdfTask<T> Function() create, [CancelToken? cancel]) async {
    late final px.PdfTask<T> task;
    try {
      task = create();
    } on ArgumentError catch (e) {
      throw PdfFailure(FailureKind.unknown, cause: e);
    }

    void onCancel() => task.cancel();
    cancel?.addListener(onCancel);
    try {
      return await task;
    } on px.PdfError catch (e) {
      throw _map(e);
    } on FileSystemException catch (e) {
      throw PdfFailure(_isNoSpace(e) ? FailureKind.outOfStorage : FailureKind.io,
          cause: e);
    } finally {
      cancel?.removeListener(onCancel);
    }
  }

  static bool _isNoSpace(FileSystemException e) {
    // errno 28 (ENOSPC) on both Android and iOS.
    return e.osError?.errorCode == 28;
  }

  static PdfFailure _map(px.PdfError error) => switch (error) {
        px.PdfPasswordRequired() =>
          PdfFailure(FailureKind.passwordRequired, cause: error),
        px.PdfWrongPassword() =>
          PdfFailure(FailureKind.wrongPassword, cause: error),
        px.PdfCancelled() => PdfFailure(FailureKind.cancelled, cause: error),
        px.PdfCorrupted() => PdfFailure(FailureKind.corruptFile, cause: error),
        px.PdfPageRangeError(:final page, :final pageCount) => PdfFailure(
            FailureKind.pageOutOfRange,
            cause: error,
            detail: 'This document has $pageCount pages, so page '
                '${page + 1} does not exist.',
          ),
        px.PdfUnsupported() => PdfFailure(FailureKind.unsupported, cause: error),
        px.PdfCryptoError() =>
          PdfFailure(FailureKind.permissionDenied, cause: error),
        px.PdfIoError() => PdfFailure(FailureKind.io, cause: error),
        px.PdfInvalidArgument() ||
        px.PdfExtractionFailed() ||
        px.PdfSearchError() ||
        px.PdfEngineError() =>
          PdfFailure(FailureKind.unknown, cause: error),
      };
}
