import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';

@immutable
class AppCardTheme extends ThemeExtension<AppCardTheme> {
  const AppCardTheme({
    required this.surface,
    required this.surfaceSecondary,
    required this.borderColor,
    required this.radius,
    required this.padding,
  });

  final Color surface;
  final Color surfaceSecondary;
  final Color borderColor;
  final BorderRadius radius;
  final EdgeInsets padding;

  static const AppCardTheme base = AppCardTheme(
    surface: AppColors.surface,
    surfaceSecondary: AppColors.surfaceTertiary,
    borderColor: AppColors.surfaceSecondary,
    radius: BorderRadius.all(Radius.circular(12)),
    padding: EdgeInsets.all(18),
  );

  @override
  AppCardTheme copyWith({
    Color? surface,
    Color? surfaceSecondary,
    Color? borderColor,
    BorderRadius? radius,
    EdgeInsets? padding,
  }) {
    return AppCardTheme(
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      borderColor: borderColor ?? this.borderColor,
      radius: radius ?? this.radius,
      padding: padding ?? this.padding,
    );
  }

  @override
  AppCardTheme lerp(ThemeExtension<AppCardTheme>? other, double t) {
    if (other is! AppCardTheme) return this;
    return AppCardTheme(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSecondary: Color.lerp(
        surfaceSecondary,
        other.surfaceSecondary,
        t,
      )!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      radius: BorderRadius.lerp(radius, other.radius, t)!,
      padding: EdgeInsets.lerp(padding, other.padding, t)!,
    );
  }
}
