import 'package:flutter/material.dart';

import '../../../core/models/pdf_tool.dart';
import '../../../core/theme/app_theme.dart';
import 'tool_card.dart';

/// A titled group of tools (requirements.md 3.1).
class ToolGroupSection extends StatelessWidget {
  const ToolGroupSection({
    super.key,
    required this.group,
    required this.tools,
    required this.onToolTap,
  });

  final ToolGroup group;
  final List<PdfTool> tools;
  final void Function(PdfTool tool) onToolTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xs,
            Insets.lg,
            Insets.xs,
            Insets.md,
          ),
          child: Text(
            group.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        _ResponsiveToolGrid(tools: tools, onToolTap: onToolTap),
      ],
    );
  }
}

/// Requirements.md 18.4: phone, large-phone and tablet breakpoints from the
/// first commit, because retrofitting a stretched phone layout is expensive.
class _ResponsiveToolGrid extends StatelessWidget {
  const _ResponsiveToolGrid({required this.tools, required this.onToolTap});

  final List<PdfTool> tools;
  final void Function(PdfTool tool) onToolTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = switch (width) {
          >= Insets.tabletBreakpoint => 4,
          >= Insets.largePhoneBreakpoint => 3,
          _ => 2,
        };

        // Cards grow with the text scale so nothing clips at the largest
        // dynamic type (requirements.md 18.2).
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final tileHeight = 162.0 + (textScale - 1).clamp(0, 2) * 64.0;
        final tileWidth =
            (width - (columns - 1) * Insets.md) / columns;

        return GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tools.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Insets.md,
            crossAxisSpacing: Insets.md,
            childAspectRatio: tileWidth / tileHeight,
          ),
          itemBuilder: (context, i) => ToolCard(
            tool: tools[i],
            onTap: () => onToolTap(tools[i]),
          ),
        );
      },
    );
  }
}
