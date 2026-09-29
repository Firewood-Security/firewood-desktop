// Single source of truth for Firewood colour. Values mirror the mobile app's
// established palette so both apps stay visually identical, while components
// differ per platform.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Base zinc surfaces (shared)
  static const Color backgroundZinc = Color(0xFF09090B);
  static const Color surfaceZinc = Color(0xFF18181B);
  static const Color cardZinc = Color(0xFF242427);
  static const Color borderZinc = Color(0xFF3F3F46);
  static const Color inputZinc = Color(0xFF141416);

  static const Color offWhite = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFE4E4E7);
  static const Color textMuted = Color(0xFFA1A1AA);

  // Flame accent
  static const Color orangeAccent = Color(0xFFFF5722);
  static const Color orangeBright = Color(0xFFFF6F40);
  static const Color orangeDark = Color(0xFFE64A19);
  static const Color orangeContainer = Color(0xFF33140A);
  static const Color orangeBorder = Color(0xFF662914);
  static const Color orangeOnContainer = Color(0xFFFFDBCE);

  // Status
  static const Color roseAccent = Color(0xFFEF4444);
  static const Color roseContainer = Color(0xFF2E1517);
  static const Color roseBorder = Color(0xFF5A2529);
  static const Color roseOnContainer = Color(0xFFFECDD3);

  static const Color mintAccent = Color(0xFF22C55E);
  static const Color emeraldAccent = Color(0xFF22C55E);
  static const Color mintContainer = Color(0xFF132A1C);
  static const Color mintBorder = Color(0xFF235432);
  static const Color mintOnContainer = Color(0xFFDCFCE7);

  static const Color periwinkleAccent = Color(0xFF818CF8);
  static const Color periwinkleContainer = Color(0xFF1B1D33);
  static const Color periwinkleBorder = Color(0xFF333866);
  static const Color periwinkleOnContainer = Color(0xFFE0E7FF);

  // Desktop surfaces — mapped to the Android dark-zinc shades so the desktop
  // app shares the same subtle grey background language.
  static const Color coal = backgroundZinc; // page background (#09090B)
  static const Color coalSoft = Color(0xFF111113);
  static const Color hearth = surfaceZinc; // panels (#18181B)
  static const Color hearthRaised = cardZinc; // raised panels (#242427)
  static const Color hearthEdge = borderZinc; // borders (#3F3F46)
  static const Color ember = Color(0xFFFF6B35);
  static const Color emberBright = Color(0xFFFF9163);
  static const Color emberDeep = Color(0xFFB23A18);
  static const Color emberGlow = Color(0x40FF6B35);

  // Hearth ink — aligned to the Android text shades.
  static const Color ash = offWhite;
  static const Color ashMuted = textMuted;
  static const Color ashFaint = Color(0xFF71717A);

  /// Shifts [color]'s HSL lightness by [delta] — subtle gradient faces for
  /// the matte soft-3D buttons (light crown, deep base).
  static Color shade(Color color, double delta) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }
}

