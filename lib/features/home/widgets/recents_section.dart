import 'package:flutter/material.dart';

import '../../../core/recents/recent_document.dart';
import '../../../core/theme/app_theme.dart';

/// Recent files strip (requirements.md 4).
///
/// Loads asynchronously and never blocks the rest of the home screen
/// (requirements.md 3.1).
class RecentsSection extends StatelessWidget {
  const RecentsSection({
    super.key,
    required this.recents,
    required this.onOpenFile,
  });

  final AsyncSnapshot<List<RecentDocument>> recents;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (recents.connectionState == ConnectionState.waiting) {
      return const _RecentsPlaceholder();
    }

    final docs = recents.data ?? const <RecentDocument>[];
    if (docs.isEmpty) {
      // Requirements.md 3.0: every empty state names the action that fills it
      // and offers that action as a button.
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No recent files yet',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Files you work on will appear here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Insets.sm),
              FilledButton.tonal(
                onPressed: onOpenFile,
                child: const Text('Open a PDF'),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: docs.length,
        separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
        itemBuilder: (context, i) => _RecentTile(document: docs[i]),
      ),
    );
  }
}

class _RecentsPlaceholder extends StatelessWidget {
  const _RecentsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 84,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.document});

  final RecentDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              document.lastOperation,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
