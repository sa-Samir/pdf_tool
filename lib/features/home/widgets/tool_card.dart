import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/models/pdf_tool.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// One tool on the home grid.
class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
    required this.tool,
    required this.onTap,
    this.allowance,
  });

  final PdfTool tool;
  final VoidCallback onTap;

  /// What is left of the free allowance, when it is known.
  final ToolAllowance? allowance;

  String? _premiumNote() {
    final current = allowance;
    if (current == null) return null; // Say nothing rather than guess.
    if (current.isPremium) return null;
    return current.isExhausted
        ? 'Free runs used'
        : '${current.remaining} free '
            '${current.remaining == 1 ? 'run' : 'runs'} left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accentFor(tool.group, theme.brightness);

    // Requirements.md 3.1: the tier is shown only where a limit applies, so a
    // free tool is never mistaken for a premium one. For a premium tool the
    // number shown is the real remaining count, not a fixed label.
    final note = tool.tierNote ??
        (tool.tier == ToolTier.premium ? _premiumNote() : null);

    return Semantics(
      button: true,
      label: note == null
          ? '${tool.label}. ${tool.description}'
          : '${tool.label}. ${tool.description}. $note',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(Insets.sm),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(Corners.iconTile),
                  ),
                  child: Icon(tool.icon, size: 22, color: accent),
                ),
                const SizedBox(height: Insets.md),
                Text(
                  tool.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Insets.xs),
                // Flexible rather than a fixed height: the card must survive any
                // text scale without overflowing (requirements.md 18.2).
                Flexible(
                  child: Text(
                    tool.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: Insets.sm),
                  _TierNote(note: note),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TierNote extends StatelessWidget {
  const _TierNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Corners.chip),
      ),
      child: Text(
        note,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
