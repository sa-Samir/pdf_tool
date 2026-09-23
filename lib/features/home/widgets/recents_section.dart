import 'package:flutter/material.dart';

import '../../../core/library/library_document.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/job_views.dart';

/// Recent files strip (requirements.md 4).
///
/// Loads asynchronously and never blocks the rest of the home screen
/// (requirements.md 3.1).
class RecentsSection extends StatelessWidget {
  const RecentsSection({
    super.key,
    required this.recents,
    required this.onOpenFile,
    required this.onSeeAll,
    required this.onOpenDocument,
  });

  final AsyncSnapshot<List<LibraryDocument>> recents;
  final VoidCallback onOpenFile;
  final VoidCallback onSeeAll;
  final void Function(LibraryDocument document) onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (recents.connectionState == ConnectionState.waiting) {
      return const _RecentsPlaceholder();
    }

    final docs = recents.data ?? const <LibraryDocument>[];
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: Insets.sm),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
            itemBuilder: (context, i) => _RecentTile(
              document: docs[i],
              onTap: () => onOpenDocument(docs[i]),
            ),
          ),
        ),
      ],
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
  const _RecentTile({required this.document, required this.onTap});

  final LibraryDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (document.favorite)
                    Icon(
                      Icons.star,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: Insets.xs),
              Text(
                document.operation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatBytes(document.sizeBytes)} · '
                '${formatRelativeTime(document.createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
