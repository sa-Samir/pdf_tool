import 'package:flutter/widgets.dart';

/// Tool groups from requirements.md 3.1. Grouping is also how the paywall is
/// explained, so these are product categories, not UI conveniences.
enum ToolGroup {
  organize('Organize'),
  capture('Capture'),
  convert('Convert'),
  optimize('Optimize'),
  editSign('Edit & Sign'),
  secure('Secure');

  const ToolGroup(this.label);
  final String label;
}

/// Release phases from requirements.md 16. Declaration order is ship order.
enum Release { v1_0, v1_1, v1_2, v1_3 }

/// The release this build ships. Tools beyond it are not displayed at all --
/// requirements.md 3.1: no "coming soon" cards, no disabled tiles, no upgrade
/// teasers for things that do not exist yet.
const Release kShippedThrough = Release.v1_0;

/// Free-tier position from requirements.md 9.
enum ToolTier {
  /// Free and unlimited. Never labelled, so free tools are never mistaken for
  /// premium ones.
  free,

  /// Free with a cap. The cap is stated on the card; the tool still opens.
  freeWithLimit,

  /// Premium, with 3 lifetime trial uses.
  premium,
}

@immutable
class PdfTool {
  const PdfTool({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.group,
    required this.release,
    required this.tier,
    this.tierNote,
    this.aliases = const <String>[],
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final ToolGroup group;
  final Release release;
  final ToolTier tier;

  /// Whether this tool derives a new document rather than editing the one it
  /// was given (requirements.md 5.2).
  ///
  /// The distinction decides what "save" means. Rotating or compressing a
  /// document produces the same document, changed -- so it can replace what it
  /// started from. Extracting pages produces a *different* document, and
  /// writing it over the original would destroy exactly what the user asked to
  /// pull out of it. Those always save alongside.
  bool get derivesNewDocument => const {
        'extract',
        'split',
        'merge',
        'images_to_pdf',
        'pdf_to_images',
      }.contains(id);

  /// Shown on the card only where a limit applies (requirements.md 3.1).
  final String? tierNote;

  /// Verbs users actually type. Requirements.md 3.1 acceptance: search matches
  /// "combine", "join", "shrink", "password" -- not only each tool's own name.
  final List<String> aliases;

  bool get isShipped => release.index <= kShippedThrough.index;

  /// Case-insensitive match over label, description and aliases.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (label.toLowerCase().contains(q)) return true;
    if (description.toLowerCase().contains(q)) return true;
    return aliases.any((a) => a.contains(q));
  }
}
