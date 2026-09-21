/// Parsing and validation for page-range input such as `1-5, 8, 11-13`
/// (requirements.md 3.5).
///
/// Pure, so it is cheap to test exhaustively, which matters: this is the one
/// place a user types something arbitrary and a mistake silently produces the
/// wrong document.
library;

/// An inclusive, one-based page range as the user writes it.
class PageRange {
  const PageRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;

  /// Zero-based indices, as the engine wants them.
  List<int> get indices => List.generate(length, (i) => start - 1 + i);

  bool overlaps(PageRange other) => start <= other.end && other.start <= end;

  @override
  String toString() => start == end ? '$start' : '$start-$end';

  @override
  bool operator ==(Object other) =>
      other is PageRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

sealed class PageRangeResult {
  const PageRangeResult();
}

class PageRangesParsed extends PageRangeResult {
  const PageRangesParsed(this.ranges);
  final List<PageRange> ranges;
}

/// A rejection that names the specific problem, not just "invalid"
/// (requirements.md 3.5 acceptance).
class PageRangesInvalid extends PageRangeResult {
  const PageRangesInvalid(this.message);
  final String message;
}

PageRangeResult parsePageRanges(String input, {required int pageCount}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const PageRangesInvalid('Enter a page or a range, like 1-5, 8.');
  }

  final parsed = <PageRange>[];
  for (final rawPart in trimmed.split(',')) {
    final part = rawPart.trim();
    if (part.isEmpty) {
      return const PageRangesInvalid('There is an empty range between commas.');
    }

    final bounds = part.split('-');
    if (bounds.length > 2) {
      return PageRangesInvalid('"$part" has too many dashes.');
    }

    final start = int.tryParse(bounds.first.trim());
    if (start == null) {
      return PageRangesInvalid('"${bounds.first.trim()}" is not a page number.');
    }
    final endText = bounds.length == 2 ? bounds[1].trim() : bounds.first.trim();
    final end = int.tryParse(endText);
    if (end == null) {
      return PageRangesInvalid('"$endText" is not a page number.');
    }

    if (start < 1 || end < 1) {
      return const PageRangesInvalid('Pages start at 1.');
    }
    if (end < start) {
      return PageRangesInvalid('"$part" runs backwards. Try $end-$start.');
    }
    if (end > pageCount) {
      return PageRangesInvalid(
        'This document has $pageCount pages, so $end does not exist.',
      );
    }

    final range = PageRange(start, end);
    for (final existing in parsed) {
      if (existing.overlaps(range)) {
        return PageRangesInvalid('$range overlaps $existing.');
      }
    }
    parsed.add(range);
  }

  return PageRangesParsed(parsed);
}
