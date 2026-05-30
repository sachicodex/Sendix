import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';

enum AppSnackBarType { offline, error, success, info }

AppSnackBarType inferSnackBarType(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('offline') || lower.contains('no internet')) {
    return AppSnackBarType.offline;
  }
  if (lower.contains('error') || lower.contains('failed')) {
    return AppSnackBarType.error;
  }
  if (lower.contains('success') || lower.contains('sent')) {
    return AppSnackBarType.success;
  }
  return AppSnackBarType.info;
}

void showAppSnackBar(
  BuildContext context,
  String message, {
  Duration? duration,
  AppSnackBarType? type,
  EdgeInsetsGeometry? padding,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    buildAppSnackBar(
      context,
      message,
      duration: duration,
      type: type,
      padding: padding,
    ),
  );
}

SnackBar buildAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackBarType? type,
  Duration? duration,
  EdgeInsetsGeometry? padding,
}) {
  final resolvedType = type ?? inferSnackBarType(message);
  final icon = switch (resolvedType) {
    AppSnackBarType.offline => Icons.wifi_off_rounded,
    AppSnackBarType.error => Icons.error_outline_rounded,
    AppSnackBarType.success => Icons.check_circle_outline_rounded,
    AppSnackBarType.info => Icons.info_outline_rounded,
  };

  final theme = Theme.of(context);
  final snackTheme = theme.snackBarTheme;
  final barWidth = MediaQuery.sizeOf(context).width * 0.97;
  final iconColor = switch (resolvedType) {
    AppSnackBarType.offline => AppColors.textSecondary,
    AppSnackBarType.error => AppColors.danger,
    AppSnackBarType.success => AppColors.success,
    AppSnackBarType.info => AppColors.primaryAccent,
  };

  return SnackBar(
    duration: duration ?? const Duration(seconds: 4),
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    content: Center(
      child: Container(
        width: barWidth,
        padding: padding ?? const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: snackTheme.backgroundColor ?? theme.colorScheme.surface,
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: barWidth - 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        snackTheme.contentTextStyle ??
                        theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
