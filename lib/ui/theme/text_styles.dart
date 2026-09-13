import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';

class AppTextStyles {
  const AppTextStyles._();

  static const String _font = 'SFProDisplay';

  static const TextStyle headline1 = TextStyle(
    fontFamily: _font,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.onBg,
  );

  static const TextStyle headline2 = TextStyle(
    fontFamily: _font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onBg,
    letterSpacing: 0.5,
  );

  static const TextStyle headline3 = TextStyle(
    fontFamily: _font,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.onBg,
    letterSpacing: 0.5,
  );

  static const TextStyle bodyText1 = TextStyle(
    fontFamily: _font,
    fontSize: 16,
    color: AppColors.onBg,
    letterSpacing: 0.3,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.bg,
  );

  // Material-style aliases retained for the existing UI.
  static const TextStyle headlineSmall = headline1;
  static const TextStyle titleLarge = headline1;
  static const TextStyle titleMedium = headline2;
  static const TextStyle titleSmall = headline3;
  static const TextStyle bodyMedium = bodyText1;
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _font,
    fontSize: 12,
    color: AppColors.onSurface,
  );
  static const TextStyle labelLarge = headline3;
}
