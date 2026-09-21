import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Hands finished files to the platform share sheet (requirements.md 6).
class ExportService {
  const ExportService();

  Future<void> share(List<File> files, {String? subject}) async {
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final f in files) XFile(f.path)],
        subject: subject,
      ),
    );
  }
}
