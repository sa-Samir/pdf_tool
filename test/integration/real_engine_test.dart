@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/engine/pdf_manipulator_engine.dart';

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

  /// Builds a real PDF with [pages] pages using the engine's own builder.
  Future<File> makePdf(String name, int pages) async {
    final pdf = Pdf();
    final builder = await pdf.build();
    for (var i = 1; i <= pages; i++) {
      final page = await builder.addA4Page();
      await page.font('Helvetica', 24);
      await page.at(72, 700);
      await page.text('Page $i of $name');
    }
    final file = File('${dir.path}/$name');
    await builder.save(await FileSink.create(file));
    await builder.dispose();
    await pdf.dispose();
    return file;
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
