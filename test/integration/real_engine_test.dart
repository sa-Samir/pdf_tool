@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/engine/pdf_manipulator_engine.dart';
import 'package:pdf_toolbox/core/pages/page_edit_session.dart';

/// Exercises the real Rust engine, not a fake. Everything else in the suite
/// runs against fakes, so without this nothing proves the facade actually
/// speaks the engine's language.
void main() {
  late Directory dir;
  late PdfManipulatorEngine engine;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('real_engine');
    engine = PdfManipulatorEngine();
  });

  tearDownAll(() async {
    await engine.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Builds a real PDF whose pages carry MARKER0..MARKERn, so page order is
  /// observable in the output rather than merely assumed.
  Future<File> makePdf(String name, int pages) async {
    final pdf = Pdf();
    final builder = await pdf.build();
    for (var i = 0; i < pages; i++) {
      final page = await builder.addA4Page();
      await page.font('Helvetica', 36);
      await page.at(72, 700);
      await page.text('MARKER$i');
    }
    final file = File('${dir.path}/$name');
    await builder.save(await FileSink.create(file));
    await builder.dispose();
    await pdf.dispose();
    return file;
  }

  /// The marker on each page of [file], in page order.
  Future<List<String>> pageOrder(File file) async {
    final pdf = Pdf();
    final doc = await pdf.open(FileSource(file));
    final markers = <String>[];
    for (var i = 0; i < doc.pageCount; i++) {
      final text = await doc.extract(pages: PdfPages.single(i));
      markers.add(RegExp(r'MARKER\d+').firstMatch(text)?.group(0) ?? '?');
    }
    await doc.dispose();
    await pdf.dispose();
    return markers;
  }

  test('inspect reads the real page count', () async {
    final file = await makePdf('three.pdf', 3);
    final info = await engine.inspect(file);
    expect(info.pageCount, 3);
    expect(info.sizeBytes, greaterThan(0));
  });

  test('merge concatenates real documents', () async {
    final a = await makePdf('a.pdf', 3);
    final b = await makePdf('b.pdf', 4);
    final out = File('${dir.path}/merged.pdf');

    final steps = <int>[];
    await engine.merge(
      inputs: [a, b],
      output: out,
      onStep: (completed, _) => steps.add(completed),
    );

    expect((await engine.inspect(out)).pageCount, 7);
    expect(steps, [1, 2, 3]);
  });

  test('extractPages writes exactly the pages asked for', () async {
    final source = await makePdf('long.pdf', 10);
    final out = File('${dir.path}/slice.pdf');

    await engine.extractPages(
      input: source,
      output: out,
      pageIndices: const [0, 1, 2, 3, 4],
    );

    expect((await engine.inspect(out)).pageCount, 5);
  });

  test('a file that is not a PDF fails as corrupt, not as a crash', () async {
    final junk = File('${dir.path}/junk.pdf');
    await junk.writeAsString('this is definitely not a pdf');

    await expectLater(
      engine.inspect(junk),
      throwsA(isA<PdfFailure>().having(
        (f) => f.kind,
        'kind',
        anyOf(FailureKind.corruptFile, FailureKind.unknown),
      )),
    );
  });

  group('page edits', () {
    test('reorders pages into the order given', () async {
      final source = await makePdf('order.pdf', 4);
      final out = File('${dir.path}/reordered.pdf');

      await engine.applyPageEdits(
        input: source,
        output: out,
        pages: const [
          PageRef(id: 0, sourceIndex: 3),
          PageRef(id: 1, sourceIndex: 0),
          PageRef(id: 2, sourceIndex: 2),
          PageRef(id: 3, sourceIndex: 1),
        ],
      );

      expect(await pageOrder(out), ['MARKER3', 'MARKER0', 'MARKER2', 'MARKER1']);
    });

    test('duplicates a page when its index repeats', () async {
      final source = await makePdf('dup.pdf', 2);
      final out = File('${dir.path}/duplicated.pdf');

      await engine.applyPageEdits(
        input: source,
        output: out,
        pages: const [
          PageRef(id: 0, sourceIndex: 0),
          PageRef(id: 1, sourceIndex: 0),
          PageRef(id: 2, sourceIndex: 1),
        ],
      );

      // The whole duplicate-page feature rests on this.
      expect(await pageOrder(out), ['MARKER0', 'MARKER0', 'MARKER1']);
    });

    test('duplicates and reorders together', () async {
      final source = await makePdf('both.pdf', 3);
      final out = File('${dir.path}/both_out.pdf');

      await engine.applyPageEdits(
        input: source,
        output: out,
        pages: const [
          PageRef(id: 0, sourceIndex: 2),
          PageRef(id: 1, sourceIndex: 0),
          PageRef(id: 2, sourceIndex: 2),
          PageRef(id: 3, sourceIndex: 2),
        ],
      );

      expect(await pageOrder(out),
          ['MARKER2', 'MARKER0', 'MARKER2', 'MARKER2']);
    });

    test('leaves no intermediate file behind after duplicating', () async {
      final source = await makePdf('clean.pdf', 2);
      final out = File('${dir.path}/clean_out.pdf');

      await engine.applyPageEdits(
        input: source,
        output: out,
        pages: const [
          PageRef(id: 0, sourceIndex: 0),
          PageRef(id: 1, sourceIndex: 0),
        ],
      );

      expect(File('${out.path}.pass1').existsSync(), isFalse);
    });

    test('drops pages that are left out', () async {
      final source = await makePdf('drop.pdf', 5);
      final out = File('${dir.path}/dropped.pdf');

      await engine.applyPageEdits(
        input: source,
        output: out,
        pages: const [
          PageRef(id: 0, sourceIndex: 1),
          PageRef(id: 1, sourceIndex: 3),
        ],
      );

      expect(await pageOrder(out), ['MARKER1', 'MARKER3']);
    });

    test('applies rotation and reports progress', () async {
      final source = await makePdf('rot.pdf', 3);
      final out = File('${dir.path}/rotated.pdf');
      final steps = <int>[];

      await engine.applyPageEdits(
        input: source,
        output: out,
        pages: const [
          PageRef(id: 0, sourceIndex: 0, rotation: 90),
          PageRef(id: 1, sourceIndex: 1, rotation: 180),
          PageRef(id: 2, sourceIndex: 2),
        ],
        onStep: (completed, _) => steps.add(completed),
      );

      expect(await pageOrder(out), ['MARKER0', 'MARKER1', 'MARKER2']);
      expect(steps, [1, 2]); // no duplicates: two passes are not needed
    });

    test('a 40-page document survives a large reshuffle', () async {
      final source = await makePdf('big.pdf', 40);
      final out = File('${dir.path}/shuffled.pdf');
      final pages = [
        for (var i = 39; i >= 0; i--) PageRef(id: i, sourceIndex: i),
      ];

      await engine.applyPageEdits(input: source, output: out, pages: pages);

      final order = await pageOrder(out);
      expect(order.first, 'MARKER39');
      expect(order.last, 'MARKER0');
      expect(order, hasLength(40));
    });
  });

  test('renders a page to PNG bytes', () async {
    final source = await makePdf('render.pdf', 2);
    final bytes = await engine.renderPage(
      input: source,
      pageIndex: 1,
      maxSize: 200,
    );

    expect(bytes.length, greaterThan(100));
    // PNG magic number.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('rendering a page past the end fails rather than hanging', () async {
    final source = await makePdf('short.pdf', 1);
    await expectLater(
      engine.renderPage(input: source, pageIndex: 9, maxSize: 200),
      throwsA(isA<PdfFailure>()),
    );
  });

  test('a page past the end is rejected with a useful message', () async {
    final source = await makePdf('five.pdf', 5);
    final out = File('${dir.path}/oops.pdf');

    await expectLater(
      engine.extractPages(
        input: source,
        output: out,
        pageIndices: const [99],
      ),
      throwsA(isA<PdfFailure>()),
    );
  });
}
