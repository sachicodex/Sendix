import 'package:flutter/material.dart';
import 'package:sendix/models/transfer.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';

class TransferProgressTile extends StatelessWidget {
  const TransferProgressTile({
    super.key,
    required this.progress,
    required this.speedBytesPerSecond,
    this.showDirectionIcon = true,
    this.isPaused = false,
    this.onPauseResume,
    this.onCancel,
  });

  final TransferProgress progress;
  final double? speedBytesPerSecond;
  final bool showDirectionIcon;
  final bool isPaused;
  final VoidCallback? onPauseResume;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final isActive = progress.status == TransferStatus.inProgress;

    final rawValue = progress.status == TransferStatus.completed
        ? 1.0
        : progress.progress.clamp(0.0, 1.0);
    final value =
        (rawValue == 0 && progress.status == TransferStatus.inProgress)
        ? 0.02
        : rawValue;
    final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);

    final speed = speedBytesPerSecond;
    final speedText = (speed == null || speed <= 0)
        ? '—'
        : '${_formatBytes(speed)}/s';

    final trailingText = isPaused
        ? 'Paused'
        : switch (progress.status) {
            TransferStatus.pending => 'Starting…',
            TransferStatus.inProgress => '$speedText • $percent%',
            TransferStatus.completed => 'Done',
            TransferStatus.failed => 'Failed',
            TransferStatus.cancelled => 'Cancelled',
          };

    final transferredText =
        '${_formatBytes(progress.transferredBytes.toDouble())} / ${_formatBytes(progress.totalBytes.toDouble())}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showDirectionIcon) ...[
              Icon(
                progress.direction == TransferDirection.send
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_download_outlined,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                progress.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleSmall,
              ),
            ),
            const SizedBox(width: 10),
            if (isActive && onPauseResume != null) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onPauseResume,
                icon: Icon(
                  isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onCancel,
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _AnimatedProgressBar(value: value),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                transferredText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              trailingText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (progress.error case final e?) ...[
          const SizedBox(height: 8),
          Text(
            e,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  static String _formatBytes(double bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 ? 0 : (value < 10 ? 1 : 0);
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final trackColor = AppColors.surfaceTertiary;
    final baseColor = AppColors.primaryAccent;
    final barHeight = 6.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: barHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(color: trackColor),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final targetWidth = (constraints.maxWidth * value.clamp(0.0, 1.0))
                  .clamp(0.0, constraints.maxWidth);
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  width: targetWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
