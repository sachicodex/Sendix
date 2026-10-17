import 'package:flutter/material.dart';
import 'package:sendix/core/error_messages.dart';
import 'package:sendix/models/transfer.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';

class TransferProgressTile extends StatelessWidget {
  const TransferProgressTile({
    super.key,
    required this.progress,
    required this.speedBytesPerSecond,
    this.showDirectionIcon = false,
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
    final value = rawValue;
    final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);

    final speed = speedBytesPerSecond;
    final remaining = speed != null && speed > 0 && progress.progress < 1
        ? _formatDuration(
            ((progress.totalBytes - progress.transferredBytes) / speed).ceil(),
          )
        : null;
    final statusText = isPaused
        ? 'Paused'
        : switch (progress.status) {
            TransferStatus.pending => 'Starting…',
            TransferStatus.inProgress =>
              [
                    if (remaining != null) '$remaining remaining',
                  ].join(' • ').isEmpty
                  ? 'Transferring'
                  : [if (remaining != null) '$remaining remaining'].join(' • '),
            TransferStatus.completed =>
              progress.direction == TransferDirection.send
                  ? 'Sent completed'
                  : 'Receive completed',
            TransferStatus.failed => 'Transfer failed',
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
        SendixProgressBar(
          value: value,
          active: progress.status == TransferStatus.pending || isActive,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '$percent%',
              style: AppTextStyles.titleMedium.copyWith(
                color: progress.status == TransferStatus.failed
                    ? AppColors.danger
                    : AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (progress.status != TransferStatus.completed)
          Text(
            transferredText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        if (progress.error case final e?) ...[
          const SizedBox(height: 8),
          Text(
            userErrorMessage(e),
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

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes < 60) return '${minutes}m ${remainder}s';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }
}

class SendixProgressBar extends StatefulWidget {
  const SendixProgressBar({
    super.key,
    required this.value,
    required this.active,
  });

  final double value;
  final bool active;

  @override
  State<SendixProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<SendixProgressBar>
    with TickerProviderStateMixin {
  late final AnimationController _progress;
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late Animation<double> _valueAnimation;

  @override
  void initState() {
    super.initState();
    final initial = widget.value.clamp(0.0, 1.0).toDouble();
    _valueAnimation = AlwaysStoppedAnimation<double>(initial);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    if (widget.active) _shimmer.repeat();
  }

  @override
  void didUpdateWidget(covariant SendixProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.value.clamp(0.0, 1.0).toDouble();
    final current = _valueAnimation.value;
    if ((target - current).abs() > 0.0001) {
      _valueAnimation = Tween<double>(
        begin: current,
        end: target,
      ).animate(CurvedAnimation(parent: _progress, curve: Curves.easeOutCubic));
      _progress.forward(from: 0);
    }
    if (widget.active && !oldWidget.active) {
      _shimmer.repeat();
    } else if (!widget.active && oldWidget.active) {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _shimmer.dispose();
    super.dispose();
  }

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
              return AnimatedBuilder(
                animation: Listenable.merge([_progress, _shimmer]),
                builder: (context, _) {
                  final animatedValue = _valueAnimation.value;
                  final targetWidth = constraints.maxWidth * animatedValue;
                  final starting = widget.active && widget.value <= 0;
                  final complete = widget.value >= 0.999;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedBuilder(
                      animation: _shimmer,
                      builder: (context, _) {
                        final gradient = complete
                            ? null
                            : starting
                            ? LinearGradient(
                                begin: Alignment(-1 + _shimmer.value * 2, 0),
                                end: Alignment(-0.5 + _shimmer.value * 2, 0),
                                colors: [
                                  baseColor.withValues(alpha: 0.35),
                                  baseColor,
                                  baseColor.withValues(alpha: 0.35),
                                ],
                              )
                            : LinearGradient(
                                begin: Alignment(-1 + _shimmer.value * 2, 0),
                                end: Alignment(-0.45 + _shimmer.value * 2, 0),
                                colors: [
                                  baseColor,
                                  baseColor,
                                  Color(0xff1E1E1E),
                                  baseColor,
                                ],
                                stops: const [0, 0.42, 0.52, 1],
                              );
                        return Container(
                          width: starting
                              ? constraints.maxWidth * 0.035
                              : targetWidth,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: complete ? baseColor : null,
                            gradient: gradient,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
