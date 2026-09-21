import 'package:flutter/foundation.dart';

/// One entry in the recent-files history (requirements.md 4).
@immutable
class RecentDocument {
  const RecentDocument({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.pageCount,
    required this.lastOperation,
    required this.modifiedAt,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final int pageCount;

  /// The tool that produced this file, e.g. "Compressed".
  final String lastOperation;
  final DateTime modifiedAt;
}
