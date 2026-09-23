import 'package:flutter/foundation.dart';

/// One page in the document being edited.
///
/// [sourceIndex] points back at a page of the original file, so duplicating a
/// page costs nothing until save. [id] is stable across reorders and unique
/// across duplicates, which is what lets selection survive an edit.
@immutable
class PageRef {
  const PageRef({
    required this.id,
    required this.sourceIndex,
    this.rotation = 0,
  });

  final int id;
  final int sourceIndex;

  /// Quarter-turns clockwise applied on top of the page's own rotation,
  /// normalised to 0, 90, 180 or 270.
  final int rotation;

  PageRef copyWith({int? id, int? rotation}) => PageRef(
        id: id ?? this.id,
        sourceIndex: sourceIndex,
        rotation: rotation ?? this.rotation,
      );

  @override
  bool operator ==(Object other) =>
      other is PageRef &&
      other.id == id &&
      other.sourceIndex == sourceIndex &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(id, sourceIndex, rotation);

  @override
  String toString() => 'PageRef(id: $id, source: $sourceIndex, rot: $rotation)';
}

@immutable
class _Snapshot {
  const _Snapshot(this.pages, this.selection);
  final List<PageRef> pages;
  final Set<int> selection;
}

/// The page-management model (requirements.md 3.6).
///
/// Holds the whole edit session so the user can reorder, rotate, delete and
/// duplicate freely and save once, with one undo stack across all of it. Pure
/// Dart on purpose: this is where the correctness lives, and it is cheap to
/// test exhaustively without a widget tree or a file.
class PageEditSession extends ChangeNotifier {
  PageEditSession({required int pageCount})
      : assert(pageCount > 0, 'a document with no pages cannot be edited'),
        _pages = [
          for (var i = 0; i < pageCount; i++) PageRef(id: i, sourceIndex: i),
        ],
        _originalCount = pageCount,
        _nextId = pageCount;

  List<PageRef> _pages;
  Set<int> _selection = <int>{};
  final int _originalCount;
  int _nextId;

  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];

  /// Cap on undo depth. Snapshots are small (a list of value objects), but an
  /// unbounded stack on a 2,000-page document is not free.
  static const maxUndoDepth = 50;

  List<PageRef> get pages => List.unmodifiable(_pages);
  Set<int> get selection => Set.unmodifiable(_selection);
  int get pageCount => _pages.length;
  int get selectedCount => _selection.length;
  bool get hasSelection => _selection.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Whether anything would actually change if saved now. Drives both the Save
  /// button and the discard-changes prompt.
  bool get isDirty {
    if (_pages.length != _originalCount) return true;
    for (var i = 0; i < _pages.length; i++) {
      if (_pages[i].sourceIndex != i || _pages[i].rotation != 0) return true;
    }
    return false;
  }

  List<PageRef> get selectedPages =>
      [for (final page in _pages) if (_selection.contains(page.id)) page];

  // ── Selection ───────────────────────────────────────────────────────────

  void toggle(int id) {
    if (!_selection.remove(id)) _selection.add(id);
    notifyListeners();
  }

  void selectAll() {
    _selection = {for (final page in _pages) page.id};
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection = <int>{};
    notifyListeners();
  }

  // ── Edits ───────────────────────────────────────────────────────────────

  /// Rotates the selection by [quarterTurns] * 90 degrees, clockwise.
  void rotateSelection(int quarterTurns) {
    if (_selection.isEmpty || quarterTurns % 4 == 0) return;
    _commit(() {
      _pages = [
        for (final page in _pages)
          if (_selection.contains(page.id))
            page.copyWith(
              rotation: (page.rotation + quarterTurns * 90) % 360,
            )
          else
            page,
      ];
    });
  }

  /// Deletes the selection. Refuses to empty the document (requirements.md
  /// 3.6) -- a zero-page PDF is not a document, it is a broken file.
  bool deleteSelection() {
    if (_selection.isEmpty || _selection.length >= _pages.length) return false;
    _commit(() {
      _pages = [
        for (final page in _pages)
          if (!_selection.contains(page.id)) page,
      ];
      _selection = <int>{};
    });
    return true;
  }

  /// Copies each selected page in immediately after itself.
  void duplicateSelection() {
    if (_selection.isEmpty) return;
    _commit(() {
      final next = <PageRef>[];
      for (final page in _pages) {
        next.add(page);
        if (_selection.contains(page.id)) {
          next.add(page.copyWith(id: _nextId++));
        }
      }
      _pages = next;
    });
  }

  /// Keeps only the selection, in its current order.
  bool extractSelection() {
    if (_selection.isEmpty) return false;
    _commit(() {
      _pages = [
        for (final page in _pages)
          if (_selection.contains(page.id)) page,
      ];
      _selection = <int>{};
    });
    return true;
  }

  /// Moves one page, using the index convention [ReorderableListView] uses:
  /// [newIndex] is measured before the moved item is removed.
  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pages.length) return;
    var target = newIndex;
    if (target > oldIndex) target--;
    target = target.clamp(0, _pages.length - 1);
    if (target == oldIndex) return;
    _commit(() {
      final next = List.of(_pages);
      next.insert(target, next.removeAt(oldIndex));
      _pages = next;
    });
  }

  /// Puts the pages back in their original order, rotations untouched.
  void restoreOriginalOrder() {
    _commit(() {
      _pages = List.of(_pages)
        ..sort((a, b) => a.sourceIndex.compareTo(b.sourceIndex));
    });
  }

  // ── Undo ────────────────────────────────────────────────────────────────

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(List.of(_pages), Set.of(_selection)));
    final snapshot = _undo.removeLast();
    _pages = List.of(snapshot.pages);
    _selection = Set.of(snapshot.selection);
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(List.of(_pages), Set.of(_selection)));
    final snapshot = _redo.removeLast();
    _pages = List.of(snapshot.pages);
    _selection = Set.of(snapshot.selection);
    notifyListeners();
  }

  void _commit(void Function() change) {
    _undo.add(_Snapshot(List.of(_pages), Set.of(_selection)));
    if (_undo.length > maxUndoDepth) _undo.removeAt(0);
    _redo.clear();
    change();
    notifyListeners();
  }
}
