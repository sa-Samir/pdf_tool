import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/util/page_ranges.dart';

void main() {
  List<PageRange>? parsed(String input, {int pageCount = 20}) {
    final result = parsePageRanges(input, pageCount: pageCount);
    return result is PageRangesParsed ? result.ranges : null;
  }

  String? error(String input, {int pageCount = 20}) {
    final result = parsePageRanges(input, pageCount: pageCount);
    return result is PageRangesInvalid ? result.message : null;
  }

  group('accepts', () {
    test('a single page', () {
      expect(parsed('7'), [const PageRange(7, 7)]);
    });

    test('a range', () {
      expect(parsed('1-5'), [const PageRange(1, 5)]);
    });

    test('the documented example', () {
      expect(parsed('1-5, 8, 11-13'), [
        const PageRange(1, 5),
        const PageRange(8, 8),
        const PageRange(11, 13),
      ]);
    });

    test('untidy spacing', () {
      expect(parsed('  1 - 3 ,   9  '), [
        const PageRange(1, 3),
        const PageRange(9, 9),
      ]);
    });

    test('the whole document', () {
      expect(parsed('1-20', pageCount: 20), [const PageRange(1, 20)]);
    });

    test('ranges given out of order, as written', () {
      expect(parsed('10-12, 1-3'), [
        const PageRange(10, 12),
        const PageRange(1, 3),
      ]);
    });
  });

  group('rejects, naming the specific problem', () {
    test('empty input', () {
      expect(error(''), contains('Enter a page'));
    });

    test('page zero', () {
      expect(error('0'), 'Pages start at 1.');
      expect(error('0-4'), 'Pages start at 1.');
    });

    test('a backwards range, suggesting the fix', () {
      expect(error('5-2'), '"5-2" runs backwards. Try 2-5.');
    });

    test('a page past the end, naming the page count', () {
      expect(error('19-21', pageCount: 20), contains('20 pages'));
      expect(error('19-21', pageCount: 20), contains('21 does not exist'));
    });

    test('overlapping ranges, naming both', () {
      expect(error('1-5, 4-8'), '4-8 overlaps 1-5.');
    });

    test('an adjacent range is not an overlap', () {
      expect(parsed('1-5, 6-8'), isNotNull);
    });

    test('non-numeric input', () {
      expect(error('abc'), '"abc" is not a page number.');
      expect(error('1-x'), '"x" is not a page number.');
    });

    test('too many dashes', () {
      expect(error('1-2-3'), contains('too many dashes'));
    });

    test('an empty segment between commas', () {
      expect(error('1,,3'), contains('empty range'));
    });
  });

  group('conversion', () {
    test('indices are zero-based and inclusive', () {
      expect(const PageRange(1, 3).indices, [0, 1, 2]);
      expect(const PageRange(7, 7).indices, [6]);
    });

    test('length counts both ends', () {
      expect(const PageRange(1, 5).length, 5);
      expect(const PageRange(4, 4).length, 1);
    });

    test('formats the way output files are named', () {
      expect(const PageRange(1, 5).toString(), '1-5');
      expect(const PageRange(8, 8).toString(), '8');
    });
  });
}
