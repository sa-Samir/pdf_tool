import 'package:flutter/material.dart';

import '../models/pdf_tool.dart';

/// Colour tokens. Nothing in the app hard-codes a colour; it comes from here or
/// from [ColorScheme].
abstract final class AppColors {
  /// The brand indigo, and the seed the whole Material scheme is derived from.
  /// Kept in sync with the launch mark (ios LaunchImage, android ic_splash_icon).
  static const brand = Color(0xFF4F46E5);

  /// Launch background, matched to the native splash so the handoff is seamless.
  static const lightSurface = Color(0xFFFFFFFF);
  static const darkSurface = Color(0xFF0F1115);

  /// Per-group accents. Grouping is how the tool grid stays scannable at 10+
  /// tools, so each group gets a colour that survives both themes.
  static const _accents = <ToolGroup, (Color light, Color dark)>{
    ToolGroup.organize: (Color(0xFF4F46E5), Color(0xFFA6A0FF)),
    ToolGroup.capture: (Color(0xFF0E7490), Color(0xFF67E8F9)),
    ToolGroup.convert: (Color(0xFF0F766E), Color(0xFF5EEAD4)),
    ToolGroup.optimize: (Color(0xFFB45309), Color(0xFFFCD34D)),
    ToolGroup.editSign: (Color(0xFF7C3AED), Color(0xFFC4B5FD)),
    ToolGroup.secure: (Color(0xFFBE123C), Color(0xFFFDA4AF)),
  };

  static Color accentFor(ToolGroup group, Brightness brightness) {
    final pair = _accents[group]!;
    return brightness == Brightness.dark ? pair.$2 : pair.$1;
  }
}
