import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';

/// Settings (requirements.md 11).
///
/// Only Theme is wired up; the rest of the section list arrives with the
/// features it configures. Unbuilt rows are absent rather than disabled.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// Requirements.md 4: clearing history also deletes the files it describes,
  /// so the wording says so and the action is confirmed.
  Future<void> _confirmClear(BuildContext context) async {
    final library = AppServicesScope.of(context).library;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This forgets every file this app has made and deletes them from '
          'the app. Files you already shared or saved elsewhere are not '
          'affected. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await library.clearAll();
    messenger.showSnackBar(
      const SnackBar(content: Text('History cleared.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.md,
              Insets.lg,
              Insets.sm,
            ),
            child: Text(
              'Appearance',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (value) {
              if (value != null) settings.themeMode = value;
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: mode,
                    title: Text(switch (mode) {
                      ThemeMode.system => 'Match device',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    }),
                  ),
              ],
            ),
          ),
          const Divider(height: Insets.xxl),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Insets.lg, 0, Insets.lg, Insets.sm),
            child: Text(
              'Files',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear history'),
            subtitle: const Text(
              'Forgets your recent files and deletes them from this app.',
            ),
            onTap: () => _confirmClear(context),
          ),
          const Divider(height: Insets.xxl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            child: Text(
              'Defaults, storage, notifications, app lock, language and '
              'subscription management arrive with the features they '
              'configure.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
