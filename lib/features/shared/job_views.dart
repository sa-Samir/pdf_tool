import 'package:flutter/material.dart';

import '../../core/engine/pdf_failure.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/theme/app_theme.dart';

/// Progress for a running operation (requirements.md 13): determinate where
/// there are countable steps, with cancellation always available.
class JobProgressView extends StatelessWidget {
  const JobProgressView({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  final JobProgress? progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progress?.fraction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              progress?.label ?? 'Working...',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Insets.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Corners.chip),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  fraction == null
                      ? ''
                      : '${(fraction * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A failure, in the words of the requirements.md 12 taxonomy. Always states
/// that the original is untouched, because that is the user's first worry.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  final PdfFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    failure.message,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (failure.recovery case final recovery?) ...[
              const SizedBox(height: Insets.sm),
              Text(
                recovery,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
            const SizedBox(height: Insets.sm),
            Text(
              'Your original file was not changed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Insets.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value < 10 ? value.toStringAsFixed(1) : value.round()} ${units[unit]}';
}
