import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/app_card_theme.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/widgets/Glass Card/glass_carrd.dart';

class SecondaryCard extends StatelessWidget {
  const SecondaryCard({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.showBorder = true,
  });

  final Widget child;
  final EdgeInsets? padding;
  final BorderRadius? radius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final theme = AppCardTheme.base;
    final effectivePadding = padding ?? theme.padding;
    final effectiveRadius = radius ?? theme.radius;

    return GlassCard(
      padding: effectivePadding,
      borderRadius: effectiveRadius,
      tintColor: AppColors.surfaceTertiary,
      tintOpacity: 0.52,
      borderColor: showBorder ? AppColors.borderFocus : Colors.transparent,
      borderOpacity: showBorder ? 0.72 : 0,
      blurSigma: 20,
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8)),
      ],
      child: child,
    );
  }
}
