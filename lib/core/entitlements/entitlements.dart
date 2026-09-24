import 'package:flutter/foundation.dart';

import 'tool_limits.dart';

/// How many free uses of a premium tool are left.
@immutable
class ToolAllowance {
  const ToolAllowance({
    required this.toolId,
    required this.used,
    required this.isPremium,
  });

  final String toolId;
  final int used;
  final bool isPremium;

  int get remaining =>
      isPremium ? ToolLimits.freeTrialUses : (ToolLimits.freeTrialUses - used).clamp(0, ToolLimits.freeTrialUses);

  bool get canUse => isPremium || remaining > 0;

  bool get isExhausted => !canUse;
}

/// Who may use what (requirements.md 9).
///
/// A single gate: nothing in the app decides for itself whether the user is
/// entitled to something.
abstract interface class Entitlements {
  /// Whether the user has bought premium. False everywhere until purchasing
  /// exists; this is the seam Phase 4 plugs into.
  bool get isPremium;

  Future<ToolAllowance> allowanceFor(String toolId);

  /// Records one use of a premium tool.
  ///
  /// Only ever called after an operation genuinely succeeded. A failure, a
  /// cancellation, or a no-op result costs the user nothing (requirements.md
  /// 3.7 and 12).
  Future<void> recordUse(String toolId);

  /// Rebuilds anything showing a count.
  Listenable get changes;
}
