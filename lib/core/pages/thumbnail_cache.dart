import 'dart:io';
import 'dart:typed_data';

import '../engine/pdf_engine.dart';
import '../engine/pdf_failure.dart';

/// Lazily renders page thumbnails and keeps a bounded number of them.
///
/// Requirements.md 3.6 acceptance: the grid must scroll over 500 pages with
/// thumbnails rendered lazily and a bounded cache. Both halves matter -- an
/// unbounded cache of rendered bitmaps is the fastest way to hit the 400 MB
/// ceiling in requirements.md 13.
class ThumbnailCache {
  ThumbnailCache({
    required PdfEngine engine,
    required File file,
    this.maxEntries = 80,
    this.maxBytes = 24 * 1024 * 1024,
    this.pixelSize = 220,
  })  : _engine = engine,
        _file = file;

  final PdfEngine _engine;
  final File _file;

  /// Hard caps. Whichever is reached first starts evicting.
  final int maxEntries;
  final int maxBytes;

  /// Longest edge of a rendered thumbnail, in pixels.
  final int pixelSize;

  /// Insertion-ordered, used as an LRU: re-reading moves an entry to the end.
  final _entries = <int, Uint8List>{};
  final _inFlight = <int, Future<Uint8List>>{};
  var _bytes = 0;
  var _disposed = false;

  int get entryCount => _entries.length;
  int get byteCount => _bytes;

  /// Already-rendered bytes for [sourceIndex], or null. Lets the UI paint
  /// synchronously on rebuild instead of flashing a placeholder.
  Uint8List? peek(int sourceIndex) {
    final hit = _entries.remove(sourceIndex);
    if (hit == null) return null;
    _entries[sourceIndex] = hit; // touch
    return hit;
  }

  /// Renders [sourceIndex] if needed. Concurrent callers for the same page
  /// share one render -- a grid scrolling fast asks for the same page from
  /// several rebuilds.
  Future<Uint8List> get(int sourceIndex) {
    final cached = peek(sourceIndex);
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[sourceIndex];
    if (pending != null) return pending;

    final future = _render(sourceIndex);
    _inFlight[sourceIndex] = future;
    return future;
  }

  Future<Uint8List> _render(int sourceIndex) async {
    try {
      final bytes = await _engine.renderPage(
        input: _file,
        pageIndex: sourceIndex,
        maxSize: pixelSize,
      );
      if (!_disposed) _store(sourceIndex, bytes);
      return bytes;
    } on PdfFailure {
      rethrow;
    } finally {
      _inFlight.remove(sourceIndex);
    }
  }

  void _store(int sourceIndex, Uint8List bytes) {
    _entries[sourceIndex] = bytes;
    _bytes += bytes.length;
    while (_entries.length > maxEntries ||
        (_bytes > maxBytes && _entries.length > 1)) {
      final oldest = _entries.keys.first;
      final evicted = _entries.remove(oldest);
      _bytes -= evicted?.length ?? 0;
    }
  }

  void dispose() {
    _disposed = true;
    _entries.clear();
    _inFlight.clear();
    _bytes = 0;
  }
}
