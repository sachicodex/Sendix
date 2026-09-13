import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.wifi_tethering_error_rounded,
    this.iconColor = AppColors.primaryAccent,
    this.iconBuilder,
    this.showIconBackground = true,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final Widget Function(double iconSize)? iconBuilder;
  final bool showIconBackground;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : double.infinity;
        final veryTight = maxH < 140;
        final tight = maxH < 180;

        final padding = veryTight ? 8.0 : (tight ? 12.0 : 24.0);
        final iconBox = veryTight ? 44.0 : (tight ? 56.0 : 72.0);
        final iconSize = veryTight ? 22.0 : (tight ? 28.0 : 34.0);
        final titleStyle = tight
            ? AppTextStyles.titleSmall
            : AppTextStyles.titleMedium;
        final messageStyle = tight
            ? AppTextStyles.bodySmall
            : AppTextStyles.bodyMedium;
        final iconWidget =
            iconBuilder?.call(iconSize) ??
            Icon(icon, color: iconColor, size: iconSize);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!veryTight) ...[
                      if (showIconBackground)
                        Container(
                          width: iconBox,
                          height: iconBox,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.surfaceTertiary,
                                AppColors.surfaceTertiary,
                              ],
                            ),
                          ),
                          child: Center(child: iconWidget),
                        )
                      else
                        iconWidget,
                      SizedBox(height: tight ? 8 : 12),
                    ],
                    Text(
                      title,
                      maxLines: tight ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: titleStyle,
                    ),
                    if (!veryTight) ...[
                      SizedBox(height: tight ? 4 : 6),
                      Text(
                        message,
                        maxLines: tight ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: messageStyle.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (action != null) ...[
                        SizedBox(height: tight ? 10 : 14),
                        action!,
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
