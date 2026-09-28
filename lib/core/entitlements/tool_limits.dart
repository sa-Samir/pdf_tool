/// The free tier, from requirements.md 9.
///
/// Kept as data in one place so the number on a card and the number the app
/// enforces can never drift apart -- which is exactly how they drifted before.
abstract final class ToolLimits {
  /// Master switch for the free tier (requirements.md 9).
  ///
  /// Off for now: every tool is unlimited, nothing advertises a cap, and no
  /// use is counted. There is nothing to buy behind the wall yet, so a wall
  /// would only be in the way.
  ///
  /// Deliberately not `const`. The tests covering enforcement flip it, and
  /// that coverage cost a shipped defect to earn -- the free tier was
  /// advertised but never applied once already, because a test asserted a
  /// hardcoded string that could not fail. It must not rot while the switch
  /// is off.
  ///
  /// Turning it back on: set this to true. Counting resumes from zero, since
  /// nothing is recorded while it is off.
  static bool enforced = false;

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
