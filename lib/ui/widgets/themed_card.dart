import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/app_card_theme.dart';

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

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: effectiveRadius,
        border: showBorder ? Border.all(color: theme.borderColor) : null,
      ),
      child: Padding(padding: effectivePadding, child: child),
    );
  }
}
