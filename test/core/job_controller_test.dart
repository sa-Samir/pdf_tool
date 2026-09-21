import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_toolbox/core/engine/pdf_failure.dart';
import 'package:pdf_toolbox/core/jobs/job_controller.dart';

void main() {
  test('reports progress and finishes with a result', () async {
    final job = JobController<String>();
    final seen = <double?>[];
    job.addListener(() => seen.add(job.progress?.fraction));

    await job.run((handle) async {
      handle.report(completed: 1, total: 4, label: 'one');
      handle.report(completed: 4, total: 4, label: 'done');
      return 'ok';
    });

    expect(job.status, JobStatus.success);
    expect(job.result, 'ok');
    expect(seen, containsAllInOrder([0.25, 1.0]));
  });

  test('a failure is surfaced through the taxonomy, not raw', () async {
    final job = JobController<void>();
    await job.run((_) async => throw const PdfFailure(FailureKind.corruptFile));

    expect(job.status, JobStatus.failure);
    expect(job.failure?.kind, FailureKind.corruptFile);
    expect(job.failure?.message, contains("can't open this PDF"));
  });

  test('an unmapped error still lands in the taxonomy', () async {
    final job = JobController<void>();
    await job.run((_) async => throw StateError('boom'));

    expect(job.status, JobStatus.failure);
    expect(job.failure?.kind, FailureKind.unknown);
  });

  test('cancellation is reported as cancelled, not failed', () async {
    final job = JobController<void>();
    final started = Completer<void>();
    final release = Completer<void>();

    final running = job.run((handle) async {
      started.complete();
      await release.future;
      handle.cancel.throwIfCancelled();
    });

    await started.future;
    job.cancel();
    release.complete();
    await running;

    expect(job.status, JobStatus.cancelled);
    // Requirements.md 12: cancellation is silent and costs nothing.
    expect(job.failure?.isSilent, isTrue);
    expect(job.failure?.consumesUse, isFalse);
  });

  test('no failure kind consumes a free-tier use', () {
    for (final kind in FailureKind.values) {
      expect(PdfFailure(kind).consumesUse, isFalse, reason: kind.name);
    }
  });

  test('passwords are never loggable', () {
    expect(const PdfFailure(FailureKind.passwordRequired).isLoggable, isFalse);
    expect(const PdfFailure(FailureKind.wrongPassword).isLoggable, isFalse);
    expect(const PdfFailure(FailureKind.corruptFile).isLoggable, isTrue);
  });

  test('a second run is ignored while one is in flight', () async {
    final job = JobController<int>();
    final release = Completer<void>();
    final first = job.run((_) async {
      await release.future;
      return 1;
    });
    await job.run((_) async => 2);
    expect(job.result, isNull);
    release.complete();
    await first;
    expect(job.result, 1);
  });
}
