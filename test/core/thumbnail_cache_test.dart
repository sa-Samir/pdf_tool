import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/pages/thumbnail_cache.dart';

import '../fakes.dart';

void main() {
  late MemoryFakeEngine engine;
  late File file;

  ThumbnailCache build({int maxEntries = 80, int maxBytes = 1 << 24}) =>
      ThumbnailCache(
        engine: engine,
        file: file,
        maxEntries: maxEntries,
        maxBytes: maxBytes,
      );

  setUp(() {
    file = File('/memory/doc.pdf');
    engine = MemoryFakeEngine({'/memory/doc.pdf': 100});
  });

  test('renders once and serves the rest from cache', () async {
    final cache = build();
    await cache.get(0);
    await cache.get(0);
    await cache.get(0);
    expect(engine.renderCount, 1);
  });

  test('concurrent requests for one page share a single render', () async {
    final cache = build();
    await Future.wait([cache.get(3), cache.get(3), cache.get(3)]);
    expect(engine.renderCount, 1);
  });

  test('peek returns nothing before a render and bytes after', () async {
    final cache = build();
    expect(cache.peek(2), isNull);
    await cache.get(2);
    expect(cache.peek(2), isNotNull);
    // peek must not trigger work of its own.
    expect(engine.renderCount, 1);
  });

  test('evicts by entry count, oldest first', () async {
    final cache = build(maxEntries: 3);
    for (var i = 0; i < 5; i++) {
      await cache.get(i);
    }
    expect(cache.entryCount, 3);
    expect(cache.peek(0), isNull, reason: 'oldest should have gone');
    expect(cache.peek(4), isNotNull);
  });

  test('reading a page keeps it from being evicted next', () async {
    final cache = build(maxEntries: 3);
    await cache.get(0);
    await cache.get(1);
    await cache.get(2);
    cache.peek(0); // touch the oldest
    await cache.get(3);

    expect(cache.peek(0), isNotNull, reason: 'touched, so not the oldest');
    expect(cache.peek(1), isNull);
  });

  test('evicts by byte budget as well as count', () async {
    final probe = build();
    final pageBytes = (await probe.get(0)).length;
    final budget = pageBytes * 2 + 1; // room for two pages, not three

    final cache = build(maxBytes: budget);
    for (var i = 0; i < 6; i++) {
      await cache.get(i);
    }
    expect(cache.entryCount, 2);
    expect(cache.byteCount, lessThanOrEqualTo(budget));
    expect(cache.peek(5), isNotNull, reason: 'newest is kept');
    expect(cache.peek(0), isNull, reason: 'oldest is evicted');
  });

  test('keeps at least one page even when it exceeds the budget', () async {
    final cache = build(maxBytes: 1);
    await cache.get(0);
    // Evicting the only entry would mean re-rendering it on every frame.
    expect(cache.entryCount, 1);
  });

  test('a page that cannot be rendered is not cached, and reports', () async {
    final cache = build();
    await expectLater(cache.get(999), throwsA(isA<PdfFailure>()));
    expect(cache.entryCount, 0);
    // A retry is allowed to try again rather than replaying a stale failure.
    await expectLater(cache.get(999), throwsA(isA<PdfFailure>()));
    expect(engine.renderCount, 2);
  });

  test('dispose drops everything it was holding', () async {
    final cache = build();
    await cache.get(0);
    expect(cache.byteCount, greaterThan(0));
    cache.dispose();
    expect(cache.entryCount, 0);
    expect(cache.byteCount, 0);
  });
}
