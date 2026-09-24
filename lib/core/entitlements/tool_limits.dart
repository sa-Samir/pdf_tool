/// The free tier, from requirements.md 9.
///
/// Kept as data in one place so the number on a card and the number the app
/// enforces can never drift apart -- which is exactly how they drifted before.
abstract final class ToolLimits {
  /// Lifetime, not daily: a premium tool can be used this many times so the
  /// user sees it work on their own documents before the wall.
  static const freeTrialUses = 3;

  static const mergeFreeFiles = 3;
  static const imagesToPdfFreeImages = 10;

  /// Free export resolution. Anything higher is premium.
  static const maxFreeDpi = 150;

  /// Free document-scanner pages, for when the scanner lands.
  static const scannerFreePages = 3;
}
