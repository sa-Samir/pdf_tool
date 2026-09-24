import 'package:flutter/material.dart';

import '../../core/entitlements/tool_limits.dart';
import '../../core/theme/app_theme.dart';

/// Shown when a free allowance has run out (requirements.md 9).
///
/// Honest about where things stand: buying premium is not built yet, so this
/// does not pretend to offer it.
class UpgradeNotice extends StatelessWidget {
  const UpgradeNotice({super.key, required this.toolLabel});

  final String toolLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    "You've used your ${ToolLimits.freeTrialUses} free "
                    '${toolLabel.toLowerCase()} runs',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            Text(
              'Premium will lift this limit. It is not on sale yet, so there '
              'is nothing to buy today.',
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

/// A quiet line showing what is left of a free allowance.
class RemainingUses extends StatelessWidget {
  const RemainingUses({super.key, required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      remaining == 1
          ? '1 free run left'
          : '$remaining of ${ToolLimits.freeTrialUses} free runs left',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
