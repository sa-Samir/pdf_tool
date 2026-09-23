import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/engine/pdf_engine.dart';
import '../../core/engine/pdf_failure.dart';
import '../../core/pages/thumbnail_cache.dart';

enum ViewerStatus { loading, needsPassword, wrongPassword, ready, failed }

/// State for the document viewer (requirements.md 3.2).
///
/// Holds the opening handshake, the page geometry and the search results, so
/// the widget stays about layout and gestures.
class ViewerController extends ChangeNotifier {
  ViewerController({required PdfEngine engine, required File file})
      : _engine = engine,
        _file = file;

  final PdfEngine _engine;
  final File _file;

  ViewerStatus _status = ViewerStatus.loading;
  List<PageGeometry> _geometry = const [];
  String? _password;
  PdfFailure? _failure;
  ThumbnailCache? _pages;

  List<TextHit> _hits = const [];
  int _currentHit = -1;
  String _query = '';
  bool _searching = false;

  ViewerStatus get status => _status;
  List<PageGeometry> get geometry => _geometry;
  int get pageCount => _geometry.length;
  PdfFailure? get failure => _failure;
  ThumbnailCache? get pages => _pages;

  List<TextHit> get hits => _hits;
  int get currentHit => _currentHit;
  bool get searching => _searching;
  String get query => _query;
  bool get hasSearch => _query.trim().isNotEmpty;

  /// Hits on one page, for the highlight overlay.
  List<TextHit> hitsOn(int pageIndex) =>
      [for (final hit in _hits) if (hit.pageIndex == pageIndex) hit];

  Future<void> open({String? password}) async {
    _status = ViewerStatus.loading;
    notifyListeners();
    try {
      final geometry =
          await _engine.pageGeometry(_file, password: password);
      _geometry = geometry;
      _password = password;
      _pages?.dispose();
      _pages = ThumbnailCache(
        engine: _engine,
        file: _file,
        password: password,
        // Rendered above screen width so zooming in stays readable.
        pixelSize: 1400,
        maxEntries: 12,
        maxBytes: 48 * 1024 * 1024,
      );
      _status = ViewerStatus.ready;
      _failure = null;
    } on PdfFailure catch (failure) {
      _failure = failure;
      _status = switch (failure.kind) {
        FailureKind.passwordRequired => ViewerStatus.needsPassword,
        FailureKind.wrongPassword => ViewerStatus.wrongPassword,
        _ => ViewerStatus.failed,
      };
    }
    notifyListeners();
  }

  Future<void> search(String query) async {
    _query = query;
    if (query.trim().isEmpty) {
      _hits = const [];
      _currentHit = -1;
      _searching = false;
      notifyListeners();
      return;
    }

    _searching = true;
    notifyListeners();
    try {
      final hits = await _engine.search(
        input: _file,
        query: query,
        password: _password,
      );
      _hits = hits;
      _currentHit = hits.isEmpty ? -1 : 0;
    } on PdfFailure {
      // A search that cannot run is reported as no matches rather than
      // taking the document down.
      _hits = const [];
      _currentHit = -1;
    }
    _searching = false;
    notifyListeners();
  }

  void clearSearch() => search('');

  /// Moves to the next hit, wrapping around. Returns the page to show.
  int? nextHit() => _step(1);

  int? previousHit() => _step(-1);

  int? _step(int delta) {
    if (_hits.isEmpty) return null;
    _currentHit = (_currentHit + delta) % _hits.length;
    if (_currentHit < 0) _currentHit += _hits.length;
    notifyListeners();
    return _hits[_currentHit].pageIndex;
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }
}
