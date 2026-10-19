import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    this.iconWidget,
    this.label,
    this.subtitle,
    this.onTap,
    this.selected = false,
    this.iconBackgroundColor,
    this.iconColor,
    this.iconContainerSize,
    this.iconSize,
    this.vertical = false,
    this.showBorder = false,
    this.showIconBackground = true,
    this.elevated = false,
    this.padding,
    this.labelColor,
    this.selectedBackgroundColor,
    this.trailing,
  });

  final IconData icon;
  final Widget? iconWidget;
  final String? label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool selected;
  final Color? iconBackgroundColor;
  final Color? iconColor;
  final double? iconContainerSize;
  final double? iconSize;
  final bool vertical;
  final bool showBorder;
  final bool showIconBackground;
  final bool elevated;
  final EdgeInsetsGeometry? padding;
  final Color? labelColor;
  final Color? selectedBackgroundColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final iconBg = iconBackgroundColor ?? AppColors.surfaceTertiary;
    final iconFg = iconWidget == null
        ? (iconColor ?? AppColors.primaryAccent)
        : (iconColor ?? Colors.transparent);
    final iconBox = iconContainerSize ?? 32;
    final iconPx = iconSize ?? 20;
    final iconChild = iconWidget ?? Icon(icon, size: iconPx, color: iconFg);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: showBorder
          ? BorderSide(
              color: elevated
                  ? AppColors.borderFocus.withValues(alpha: 0.9)
                  : AppColors.surfaceTertiary,
            )
          : BorderSide.none,
    );
    final contentPadding =
        padding ??
        (vertical
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: Colors.transparent,
          shape: shape,
          elevation: elevated ? 4 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? (selectedBackgroundColor ??
                        AppColors.primary.withValues(alpha: 0.1))
                  : Colors.white.withValues(alpha: 0.035),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.055),
                  Colors.white.withValues(alpha: 0.018),
                  Colors.transparent,
                ],
                stops: const [0, 0.2, 1],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.12),
              ),
              boxShadow: [
                if (elevated)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: contentPadding,
                child: vertical
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (showIconBackground)
                            Container(
                              width: iconBox,
                              height: iconBox,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: iconBg,
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: iconPx,
                                  height: iconPx,
                                  child: iconChild,
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              width: iconBox,
                              height: iconBox,
                              child: Center(
                                child: SizedBox(
                                  width: iconPx,
                                  height: iconPx,
                                  child: iconChild,
                                ),
                              ),
                            ),
                          if (label != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              label!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.labelLarge.copyWith(
                                color:
                                    labelColor ??
                                    AppTextStyles.labelLarge.color,
                              ),
                            ),
                          ],
                          if (subtitle case final s?) ...[
                            const SizedBox(height: 4),
                            Text(
                              s,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          if (showIconBackground)
                            Container(
                              width: iconBox,
                              height: iconBox,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: iconBg,
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: iconPx,
                                  height: iconPx,
                                  child: iconChild,
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              width: iconBox,
                              height: iconBox,
                              child: Center(
                                child: SizedBox(
                                  width: iconPx,
                                  height: iconPx,
                                  child: iconChild,
                                ),
                              ),
                            ),
                          if (label != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    label!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color:
                                          labelColor ??
                                          AppTextStyles.labelLarge.color,
                                    ),
                                  ),
                                  if (subtitle case final s?) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      s,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            trailing!,
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
