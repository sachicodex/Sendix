import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Branding
  static const Color primary = Color(0xFFC8F902);
  static const Color secondary = Color(0xFFA0C702);
  static const Color tertiary = Color(0xFF789501);

  // Natural
  static const Color bg = Color(0xFF020202);
  static const Color surface = Color(0xFF161616);
  static const Color onBg = Color(0xFFF4F4F5);
  static const Color onSurface = Color(0xFFD4D4D8);
  static const Color onTertiary = Color(0xFFA1A1AA);

  // Borders and status colors
  static const Color border = Color(0xFF2A2A2A);
  static const Color borderFocus = Color(0xFF3A3A3A);
  static const Color divider = Color(0xFF1F242C);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // Compatibility names used by existing widgets.
  static const Color background = bg;
  static const Color textPrimary = onBg;
  static const Color textSecondary = onSurface;
  static const Color textTertiary = onTertiary;
  static const Color primaryAccent = primary;
  static const Color danger = error;
  static const Color surfaceSecondary =  Color(0xFF1E1E1E);
  static const Color surfaceTertiary = Color(0xFF1E1E1E);
  static const Color appBar = surface;
}
