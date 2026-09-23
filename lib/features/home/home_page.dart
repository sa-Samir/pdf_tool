import 'package:flutter/material.dart';

import '../../core/catalog/tool_catalog.dart';
import '../../core/models/pdf_tool.dart';
import '../../core/recents/recent_document.dart';
import '../../core/recents/recents_repository.dart';
import '../../core/theme/app_theme.dart';
import '../merge/merge_page.dart';
import '../pages/page_grid_page.dart';
import '../settings/settings_page.dart';
import '../split/split_page.dart';
import '../tool/tool_placeholder_page.dart';
import 'widgets/recents_section.dart';
import 'widgets/tool_grid.dart';
import 'widgets/tool_search_field.dart';

/// The home screen (requirements.md 3.1).
///
/// Renders and is interactive immediately; recents arrive asynchronously.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.recentsRepository = const EmptyRecentsRepository()});

  final RecentsRepository recentsRepository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  late Future<List<RecentDocument>> _recents;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _recents = widget.recentsRepository.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Tools that are actually built. Everything else still lands on the
  /// placeholder, which says so rather than pretending.
  static Widget _screenFor(PdfTool tool) => switch (tool.id) {
        'merge' => const MergePage(),
        'split' => const SplitPage(),
        // Five tools, one screen: the page grid serves them all
        // (requirements.md 3.6).
        'reorder' ||
        'rotate' ||
        'delete_pages' ||
        'duplicate' ||
        'extract' =>
          PageGridPage(tool: tool),
        _ => ToolPlaceholderPage(tool: tool),
      };

  void _openTool(PdfTool tool) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _screenFor(tool)),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  void _openFile() {
    // The import layer is Phase 1 work (roadmap.md 5); nothing can be opened
    // yet, and pretending otherwise would be worse than saying so.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('File import arrives with the import layer.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = ToolCatalog.grouped(query: _query);
    final isSearching = _query.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              titleSpacing: Insets.lg,
              title: const Text(
                'PDF Toolbox',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                ),
                const SizedBox(width: Insets.sm),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                0,
                Insets.lg,
                Insets.xxl,
              ),
              sliver: SliverList.list(
                children: [
                  ToolSearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  if (!isSearching) ...[
                    const SizedBox(height: Insets.lg),
                    FutureBuilder<List<RecentDocument>>(
                      future: _recents,
                      builder: (context, snapshot) => RecentsSection(
                        recents: snapshot,
                        onOpenFile: _openFile,
                      ),
                    ),
                  ],
                  if (groups.isEmpty)
                    _NoToolsFound(query: _query)
                  else
                    for (final entry in groups.entries)
                      ToolGroupSection(
                        group: entry.key,
                        tools: entry.value,
                        onToolTap: _openTool,
                      ),
                  const SizedBox(height: Insets.xl),
                  Center(
                    child: Text(
                      'Everything runs on this device.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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

class _NoToolsFound extends StatelessWidget {
  const _NoToolsFound({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.xxl),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: Insets.md),
          Text('No tool matches "$query"', style: theme.textTheme.titleSmall),
          const SizedBox(height: Insets.xs),
          Text(
            'Try "merge", "shrink" or "sign".',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
