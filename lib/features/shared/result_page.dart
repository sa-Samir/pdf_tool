import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../viewer/viewer_page.dart';
import 'job_views.dart';

/// What the user sees after an operation succeeds (requirements.md 6).
class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    required this.title,
    required this.files,
    this.summary,
  });

  final String title;
  final List<File> files;

  /// One line of honest detail, e.g. "4 files from 27 pages".
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = AppServicesScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Insets.lg),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Text(
                          summary ?? '${files.length} file${files.length == 1 ? '' : 's'} saved',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  for (final file in files) _ResultTile(file: file),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => services.export.share(files),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
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

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.file});

  final File file;

  bool get _isPdf => p.extension(file.path).toLowerCase() == '.pdf';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Card(
        child: ListTile(
          onTap: _isPdf
              ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfViewerPage(file: file),
                    ),
                  )
              : null,
          trailing: _isPdf ? const Icon(Icons.chevron_right) : null,
          leading: Icon(
            Icons.picture_as_pdf_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            p.basename(file.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: FutureBuilder<int>(
            future: file.length(),
            builder: (context, snapshot) => Text(
              snapshot.hasData ? formatBytes(snapshot.data!) : '',
            ),
          ),
        ),
      ),
    );
  }
}
