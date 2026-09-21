import 'package:flutter/material.dart';

import '../../core/models/pdf_tool.dart';
import '../../core/theme/app_theme.dart';

/// Stands in for a tool screen until the tool is built.
///
/// Deliberately blunt about not being implemented: a convincing-looking screen
/// that silently does nothing is the worst outcome for whoever picks this up.
class ToolPlaceholderPage extends StatelessWidget {
  const ToolPlaceholderPage({super.key, required this.tool});

  final PdfTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tool.label)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tool.icon, size: 44, color: theme.colorScheme.primary),
                const SizedBox(height: Insets.lg),
                Text(
                  tool.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Insets.md),
                Text(
                  'Not built yet. This tool needs the engine facade, the job '
                  'runner and the import layer, which are Phase 1 work; the '
                  'tool itself lands in Phase 3.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
