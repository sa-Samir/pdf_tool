import 'package:flutter/material.dart';

import '../../core/files/save_target.dart';
import '../../core/theme/app_theme.dart';

/// Asks whether to replace the document or save a copy (requirements.md 5.2).
///
/// Only shown for documents the app owns. Replacing is deliberately the
/// second option and is never the default: the safe choice should be the easy
/// one, and a copy can always be deleted afterwards while an overwrite cannot
/// be undone.
Future<SaveTarget?> askSaveTarget(
  BuildContext context, {
  required String documentName,
  required String changeSummary,
}) =>
    showModalBottomSheet<SaveTarget>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SaveChoiceSheet(
        documentName: documentName,
        changeSummary: changeSummary,
      ),
    );

class _SaveChoiceSheet extends StatelessWidget {
  const _SaveChoiceSheet({
    required this.documentName,
    required this.changeSummary,
  });

  final String documentName;
  final String changeSummary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Insets.lg, 0, Insets.lg, Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save changes',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              changeSummary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.lg),
            _Option(
              icon: Icons.note_add_outlined,
              title: 'Save as a new file',
              subtitle: '$documentName stays as it is.',
              onTap: () => Navigator.of(context).pop(SaveTarget.newFile),
              emphasised: true,
            ),
            const SizedBox(height: Insets.sm),
            _Option(
              icon: Icons.save_outlined,
              title: 'Replace $documentName',
              subtitle: 'The old version is gone for good.',
              onTap: () =>
                  Navigator.of(context).pop(SaveTarget.replaceOriginal),
            ),
            const SizedBox(height: Insets.md),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: emphasised ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: emphasised
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, maxLines: 2),
      ),
    );
  }
}
