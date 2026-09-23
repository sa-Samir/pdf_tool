import 'package:flutter/material.dart';

import '../../core/engine/compression.dart';
import '../../core/engine/pdf_failure.dart';
import '../../core/files/file_importer.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../shared/job_views.dart';
import '../shared/result_page.dart';
import 'compress_operation.dart';
import 'widgets/compare_preview.dart';

/// Compress (requirements.md 3.7).
///
/// The honesty rules live here: never promise a percentage up front, report the
/// real numbers afterwards, and treat "we could not make this smaller" as a
/// first-class outcome rather than dressing up a 1% saving.
class CompressPage extends StatefulWidget {
  const CompressPage({super.key});

  @override
  State<CompressPage> createState() => _CompressPageState();
}

class _CompressPageState extends State<CompressPage> {
  final _job = JobController<CompressionOutcome>();

  ImportedDocument? _document;
  CompressionOutlook? _outlook;
  CompressionLevel _level = CompressionLevel.balanced;
  PdfFailure? _failure;
  bool _inspecting = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _job.addListener(_onJobChanged);
  }

  @override
  void dispose() {
    _job
      ..removeListener(_onJobChanged)
      ..dispose();
    // A result the user never settled must not leave its workspace behind.
    _job.result?.discard();
    super.dispose();
  }

  void _onJobChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _choose() async {
    setState(() => _failure = null);
    final services = AppServicesScope.of(context);
    try {
      final picked = await services.importer.pickPdfs(multiple: false);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _document = picked.first;
        _outlook = null;
        _inspecting = true;
      });

      final outlook =
          await services.engine.inspectForCompression(picked.first.file);
      if (mounted) {
        setState(() {
          _outlook = outlook;
          _inspecting = false;
        });
      }
    } on PdfFailure catch (failure) {
      if (mounted) {
        setState(() {
          _failure = failure;
          _inspecting = false;
          _document = null;
        });
      }
    }
  }

  void _run() {
    final services = AppServicesScope.of(context);
    final source = _document!.file;
    final level = _level;
    _job.run((handle) => compressDocument(
          services: services,
          source: source,
          level: level,
          handle: handle,
        ));
  }

  Future<void> _keep(CompressionOutcome outcome) async {
    setState(() => _saving = true);
    final services = AppServicesScope.of(context);
    final navigator = Navigator.of(context);
    final saved = await outcome.keep(services);
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultPage(
          title: 'Compressed',
          files: [saved],
          summary: '${formatBytes(outcome.result.originalBytes)} → '
              '${formatBytes(outcome.result.compressedBytes)} · '
              'saved ${outcome.result.savedPercent}%',
        ),
      ),
    );
  }

  Future<void> _discard(CompressionOutcome outcome) async {
    await outcome.discard();
    if (mounted) _job.reset();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _job.result;

    return Scaffold(
      appBar: AppBar(title: const Text('Compress')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Insets.lg),
          children: [
            if (_failure case final failure?) ...[
              FailureView(failure: failure),
              const SizedBox(height: Insets.lg),
            ],
            if (_job.failure case final failure?) ...[
              FailureView(failure: failure, onRetry: _run),
              const SizedBox(height: Insets.lg),
            ],
            if (_document == null)
              _ChooseCard(onChoose: _choose)
            else if (outcome != null)
              _Outcome(
                outcome: outcome,
                saving: _saving,
                onKeep: () => _keep(outcome),
                onDiscard: () => _discard(outcome),
              )
            else
              ..._setup(),
          ],
        ),
      ),
    );
  }

  List<Widget> _setup() {
    final theme = Theme.of(context);
    final outlook = _outlook;
    final running = _job.isRunning;

    return [
      Card(
        child: ListTile(
          leading: Icon(
            Icons.picture_as_pdf_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            _document!.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _inspecting || outlook == null
                ? 'Checking what is in it...'
                : '${outlook.pageCount} pages · '
                    '${formatBytes(outlook.sizeBytes)}',
          ),
          trailing: TextButton(
            onPressed: running ? null : _choose,
            child: const Text('Change'),
          ),
        ),
      ),
      if (outlook != null) ...[
        const SizedBox(height: Insets.lg),
        _OutlookCard(outlook: outlook, level: _level),
        const SizedBox(height: Insets.lg),
        Text(
          'How small?',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: Insets.md),
        SegmentedButton<CompressionLevel>(
          segments: [
            for (final level in CompressionLevel.values)
              ButtonSegment(value: level, label: Text(level.label)),
          ],
          selected: {_level},
          onSelectionChanged: running
              ? null
              : (selection) => setState(() => _level = selection.first),
        ),
        const SizedBox(height: Insets.sm),
        Text(
          _level.hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Insets.lg),
        if (running)
          JobProgressView(progress: _job.progress, onCancel: _job.cancel)
        else
          FilledButton(
            onPressed: _run,
            child: const Text('Compress'),
          ),
        const SizedBox(height: Insets.md),
        Text(
          'Text stays text. Pages are never turned into pictures, so the '
          'result is still selectable and searchable.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }
}

/// What we can say before running, and nothing more (requirements.md 3.7).
class _OutlookCard extends StatelessWidget {
  const _OutlookCard({required this.outlook, required this.level});

  final CompressionOutlook outlook;
  final CompressionLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shrinks = outlook.likelyToShrink;

    return Card(
      color: shrinks ? null : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              shrinks ? Icons.compress : Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shrinks
                        ? 'This should get a lot smaller'
                        : "This one probably won't shrink",
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shrinks
                        ? 'Most of this file is images, across '
                            '${outlook.pagesWithImages} of '
                            '${outlook.pageCount} pages. Scanned documents '
                            'typically lose around '
                            '${level.typicalSavingOnScans}% at this setting.'
                        : 'It is text and vector graphics, which are already '
                            'small. Compressing works on images, so there is '
                            'little here to remove. You can still try.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.outcome,
    required this.saving,
    required this.onKeep,
    required this.onDiscard,
  });

  final CompressionOutcome outcome;
  final bool saving;
  final VoidCallback onKeep;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = outcome.result;
    final services = AppServicesScope.of(context);

    if (result.isNoOp) {
      // Requirements.md 3.7: say so plainly, offer to discard, and charge
      // nothing for it.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Already optimized',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    "We couldn't make this meaningfully smaller "
                    '(${formatBytes(result.originalBytes)} → '
                    '${formatBytes(result.compressedBytes)}). That usually '
                    'means it is already text, or it was compressed before.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    "This didn't use one of your free compressions.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.lg),
          FilledButton(onPressed: onDiscard, child: const Text('Discard')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              children: [
                _Row(label: 'Original', value: formatBytes(result.originalBytes)),
                const SizedBox(height: Insets.sm),
                _Row(
                  label: 'Compressed',
                  value: formatBytes(result.compressedBytes),
                ),
                const Divider(height: Insets.xl),
                _Row(
                  label: 'Saved',
                  value: '${result.savedPercent}%',
                  emphasis: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.lg),
        ComparePreview(
          engine: services.engine,
          original: outcome.source,
          compressed: outcome.file,
        ),
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: saving ? null : onDiscard,
                child: const Text('Discard'),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: FilledButton(
                onPressed: saving ? null : onKeep,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasis
        ? theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          )
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )),
        Text(value, style: style),
      ],
    );
  }
}

class _ChooseCard extends StatelessWidget {
  const _ChooseCard({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
      child: Column(
        children: [
          Icon(Icons.compress, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: Insets.lg),
          Text('Make a large PDF smaller',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: Insets.xs),
          Text(
            'Works best on scans and photos. We will show you the real '
            'numbers before you keep anything.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Insets.xl),
          FilledButton.icon(
            onPressed: onChoose,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose a PDF'),
          ),
        ],
      ),
    );
  }
}
