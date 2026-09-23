import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/pages/page_edit_session.dart';

void main() {
  late PageEditSession session;

  setUp(() => session = PageEditSession(pageCount: 5));

  /// The document as source-page numbers, which is what a saved file would be.
  List<int> order() => [for (final p in session.pages) p.sourceIndex];
  List<int> rotations() => [for (final p in session.pages) p.rotation];
  void selectAt(List<int> positions) {
    for (final i in positions) {
      session.toggle(session.pages[i].id);
    }
  }

  group('initial state', () {
    test('mirrors the document and is not dirty', () {
      expect(order(), [0, 1, 2, 3, 4]);
      expect(session.isDirty, isFalse);
      expect(session.canUndo, isFalse);
      expect(session.hasSelection, isFalse);
    });
  });

  group('selection', () {
    test('toggles on and off', () {
      selectAt([0, 2]);
      expect(session.selectedCount, 2);
      selectAt([0]);
      expect(session.selectedCount, 1);
    });

    test('select all then clear', () {
      session.selectAll();
      expect(session.selectedCount, 5);
      session.clearSelection();
      expect(session.hasSelection, isFalse);
    });

    test('selecting alone is not a change', () {
      session.selectAll();
      expect(session.isDirty, isFalse);
      expect(session.canUndo, isFalse);
    });
  });

  group('rotate', () {
    test('turns only the selection', () {
      selectAt([1, 3]);
      session.rotateSelection(1);
      expect(rotations(), [0, 90, 0, 90, 0]);
      expect(session.isDirty, isTrue);
    });

    test('accumulates and wraps at a full turn', () {
      selectAt([0]);
      session.rotateSelection(1);
      session.rotateSelection(1);
      expect(rotations().first, 180);
      session.rotateSelection(2);
      expect(rotations().first, 0);
    });

    test('anticlockwise normalises to a positive angle', () {
      selectAt([0]);
      session.rotateSelection(-1);
      expect(rotations().first, 270);
    });

    test('a full turn leaves the document clean', () {
      selectAt([0]);
      session.rotateSelection(4);
      expect(session.isDirty, isFalse);
    });
  });

  group('delete', () {
    test('removes the selection and clears it', () {
      selectAt([1, 3]);
      expect(session.deleteSelection(), isTrue);
      expect(order(), [0, 2, 4]);
      expect(session.hasSelection, isFalse);
    });

    test('refuses to empty the document', () {
      session.selectAll();
      expect(session.deleteSelection(), isFalse);
      expect(session.pageCount, 5);
      expect(session.isDirty, isFalse);
    });

    test('does nothing with no selection', () {
      expect(session.deleteSelection(), isFalse);
      expect(session.canUndo, isFalse);
    });
  });

  group('duplicate', () {
    test('inserts each copy directly after its page', () {
      selectAt([1]);
      session.duplicateSelection();
      expect(order(), [0, 1, 1, 2, 3, 4]);
    });

    test('a copy gets its own identity, so selection does not spread', () {
      selectAt([1]);
      session.duplicateSelection();
      final ids = [for (final p in session.pages) p.id];
      expect(ids.toSet().length, ids.length);
      expect(session.selectedCount, 1);
    });

    test('carries the rotation of the page it copies', () {
      selectAt([0]);
      session.rotateSelection(1);
      session.duplicateSelection();
      expect(rotations().take(2), [90, 90]);
    });

    test('duplicating several keeps each next to its original', () {
      selectAt([0, 4]);
      session.duplicateSelection();
      expect(order(), [0, 0, 1, 2, 3, 4, 4]);
    });
  });

  group('extract', () {
    test('keeps only the selection, in document order', () {
      selectAt([3, 1]);
      expect(session.extractSelection(), isTrue);
      expect(order(), [1, 3]);
    });

    test('does nothing with no selection', () {
      expect(session.extractSelection(), isFalse);
      expect(session.pageCount, 5);
    });
  });

  group('move', () {
    test('moves a page later', () {
      session.move(0, 3);
      expect(order(), [1, 2, 0, 3, 4]);
    });

    test('moves a page earlier', () {
      session.move(4, 1);
      expect(order(), [0, 4, 1, 2, 3]);
    });

    test('a move onto itself changes nothing', () {
      session.move(2, 2);
      expect(order(), [0, 1, 2, 3, 4]);
      expect(session.canUndo, isFalse);
    });

    test('an out-of-range index is ignored rather than throwing', () {
      session.move(99, 0);
      expect(order(), [0, 1, 2, 3, 4]);
    });

    test('restoring the original order undoes a shuffle', () {
      session.move(4, 0);
      session.move(3, 0);
      expect(order(), isNot([0, 1, 2, 3, 4]));
      session.restoreOriginalOrder();
      expect(order(), [0, 1, 2, 3, 4]);
    });
  });

  group('undo and redo', () {
    test('one undo stack spans every kind of edit', () {
      selectAt([0]);
      session.rotateSelection(1);
      session.duplicateSelection();
      session.clearSelection();
      selectAt([4]);
      session.deleteSelection();

      expect(order(), [0, 0, 1, 2, 4]);
      session.undo();
      expect(order(), [0, 0, 1, 2, 3, 4]);
      session.undo();
      expect(order(), [0, 1, 2, 3, 4]);
      expect(rotations().first, 90);
      session.undo();
      expect(rotations().first, 0);
      expect(session.isDirty, isFalse);
    });

    test('redo replays what undo took back', () {
      selectAt([1]);
      session.deleteSelection();
      session.undo();
      expect(session.pageCount, 5);
      session.redo();
      expect(order(), [0, 2, 3, 4]);
    });

    test('a new edit clears the redo stack', () {
      selectAt([1]);
      session.deleteSelection();
      session.undo();
      expect(session.canRedo, isTrue);
      selectAt([0]);
      session.rotateSelection(1);
      expect(session.canRedo, isFalse);
    });

    test('undo restores the selection it was made with', () {
      selectAt([0, 1]);
      session.duplicateSelection();
      session.clearSelection();
      session.undo();
      expect(session.selectedCount, 2);
    });

    test('undo and redo at the ends are harmless', () {
      session.undo();
      session.redo();
      expect(order(), [0, 1, 2, 3, 4]);
    });

    test('the undo stack is bounded', () {
      for (var i = 0; i < PageEditSession.maxUndoDepth + 20; i++) {
        selectAt([0]);
        session.rotateSelection(1);
        session.clearSelection();
      }
      var undos = 0;
      while (session.canUndo && undos < 500) {
        session.undo();
        undos++;
      }
      expect(undos, lessThanOrEqualTo(PageEditSession.maxUndoDepth));
    });
  });

  group('isDirty', () {
    test('is false again once edits are undone', () {
      selectAt([0]);
      session.rotateSelection(1);
      expect(session.isDirty, isTrue);
      session.undo();
      expect(session.isDirty, isFalse);
    });

    test('a reorder counts as a change even with the same pages', () {
      session.move(0, 2);
      expect(session.isDirty, isTrue);
    });

    test('notifies listeners on every edit', () {
      var notifications = 0;
      session.addListener(() => notifications++);
      selectAt([0]);
      session.rotateSelection(1);
      session.undo();
      expect(notifications, 3);
    });
  });
}
