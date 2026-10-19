import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:open_filex/open_filex.dart';
import 'package:sendix/features/receive/receive_controller.dart';
import 'package:sendix/models/transfer.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';
import 'package:sendix/ui/widgets/empty_state.dart';
import 'package:sendix/ui/widgets/transfer_progress_tile.dart';
import 'package:sendix/ui/widgets/transfer_speed_tracker.dart';
import 'package:sendix/widgets/Glass Card/glass_carrd.dart';

class ReceivePage extends StatefulWidget {
  const ReceivePage({
    super.key,
    required this.controller,
    this.outgoingTransfers,
    this.outgoingStartTimeFor,
    this.desktopLayout = false,
  });

  final ReceiveController controller;
  final ValueListenable<List<TransferProgress>>? outgoingTransfers;
  final DateTime? Function(String transferId)? outgoingStartTimeFor;
  final bool desktopLayout;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final _speedTracker = TransferSpeedTracker();
  _ActivityFilter _activityFilter = _ActivityFilter.all;
  static const String _receiveLottieAsset = 'assets/lottie/Pulse.json';
  late final Future<ByteData> _receiveLottieData = rootBundle.load(
    _receiveLottieAsset,
  );

  Widget _buildReceiveEmptyIcon(double iconSize) {
    final lottieSize = iconSize * 2;
    return FutureBuilder<ByteData>(
      future: _receiveLottieData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return SizedBox(
            width: 100,
            height: 100,
            child: Lottie.asset(
              _receiveLottieAsset,
              repeat: true,
              fit: BoxFit.contain,
            ),
          );
        }
        return SizedBox(width: lottieSize, height: lottieSize);
      },
    );
  }

  Future<void> _openLocation(String filePath) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await Process.run('explorer.exe', ['/select,', filePath]);
        return;
      } catch (_) {}
    }

    await OpenFilex.open(File(filePath).parent.path);
  }

  Future<void> _showReceivedActions(TransferProgress progress) async {
    final path = progress.localPath;
    final control = widget.controller.controlFor(progress.transferId);
    final isInProgress = progress.status == TransferStatus.inProgress;
    final canOpenLocation = path != null && path.trim().isNotEmpty;
    final canDelete =
        progress.status == TransferStatus.completed && canOpenLocation;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 28,
                  offset: Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.cloud_download_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Received file',
                            style: AppTextStyles.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            progress.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (isInProgress) ...[
                  _actionMenuTile(
                    icon: control?.paused.value == true
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    title: control?.paused.value == true ? 'Resume' : 'Pause',
                    enabled: control != null,
                    onTap: control == null
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            if (control.paused.value) {
                              widget.controller.resumeTransfer(
                                progress.transferId,
                              );
                            } else {
                              widget.controller.pauseTransfer(
                                progress.transferId,
                              );
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  _actionMenuTile(
                    icon: Icons.close_rounded,
                    title: 'Cancel transfer',
                    iconColor: AppColors.danger,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.controller.cancelTransfer(progress.transferId);
                    },
                  ),
                ],
                if (canOpenLocation) ...[
                  if (isInProgress) const SizedBox(height: 8),
                  _actionMenuTile(
                    icon: Icons.folder_open_rounded,
                    title: 'Open location',
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _openLocation(path);
                    },
                  ),
                ],
                if (canDelete) ...[
                  const SizedBox(height: 8),
                  _actionMenuTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'Delete from device',
                    iconColor: AppColors.danger,
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      try {
                        await File(path).delete();
                      } catch (_) {}
                      widget.controller.dismissTransfer(progress.transferId);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    Color? iconColor,
    bool enabled = true,
  }) {
    final active = enabled && onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: active ? 0.055 : 0.025),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: active
                    ? (iconColor ?? AppColors.textPrimary)
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (active)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[widget.controller.transfers];
    if (widget.outgoingTransfers != null) {
      listenables.add(widget.outgoingTransfers!);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final transfers = [
          ...widget.controller.transfers.value,
          ...?widget.outgoingTransfers?.value,
        ];
        final ordered = List<TransferProgress>.from(transfers)
          ..sort((a, b) {
            final aStart = _startTimeFor(a)?.millisecondsSinceEpoch ?? 0;
            final bStart = _startTimeFor(b)?.millisecondsSinceEpoch ?? 0;
            if (aStart != bStart) return bStart.compareTo(aStart);
            return a.transferId.compareTo(b.transferId);
          });

        final filtered = ordered.where(_matchesFilter).toList();

        Widget header() => Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    size: 20,
                    color: AppColors.primaryAccent,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Activity', style: AppTextStyles.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Live sends & receives',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ActivityFilter.values.map((filter) {
                  return ChoiceChip(
                    label: Text(filter.label),
                    selected: _activityFilter == filter,
                    onSelected: (_) => setState(() => _activityFilter = filter),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceSecondary,
                    labelStyle: AppTextStyles.bodySmall.copyWith(
                      color: _activityFilter == filter
                          ? AppColors.bg
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: _activityFilter == filter
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
            ],
          ),
        );

        Widget transferCard(TransferProgress progress) {
          final c = widget.controller.controlFor(progress.transferId);

          return GlassCard(
            padding: EdgeInsets.zero,
            tintColor: Colors.white,
            tintOpacity: 0.045,
            borderColor: Colors.white,
            borderOpacity: 0.13,
            blurSigma: 20,
            onTap: progress.direction == TransferDirection.receive
                ? () => _showReceivedActions(progress)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: c == null
                  ? TransferProgressTile(
                      progress: progress,
                      speedBytesPerSecond: _speedTracker.update(progress),
                      isPaused: false,
                    )
                  : ValueListenableBuilder<bool>(
                      valueListenable: c.paused,
                      builder: (context, paused, _) {
                        return TransferProgressTile(
                          progress: progress,
                          speedBytesPerSecond: _speedTracker.update(progress),
                          isPaused: paused,
                          onPauseResume:
                              progress.status == TransferStatus.inProgress
                              ? () {
                                  if (c.paused.value) {
                                    widget.controller.resumeTransfer(
                                      progress.transferId,
                                    );
                                  } else {
                                    widget.controller.pauseTransfer(
                                      progress.transferId,
                                    );
                                  }
                                }
                              : null,
                          onCancel: progress.status == TransferStatus.inProgress
                              ? () => widget.controller.cancelTransfer(
                                  progress.transferId,
                                )
                              : null,
                        );
                      },
                    ),
            ),
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.desktopLayout ? 0 : 16,
            16,
            96,
          ),
          children: [
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              tintColor: Colors.white,
              tintOpacity: 0.055,
              borderColor: Colors.white,
              borderOpacity: 0.14,
              blurSigma: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header(),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: EmptyState(
                        title: ordered.isEmpty
                            ? 'Ready to receive'
                            : 'No matching activity',
                        message: ordered.isEmpty
                            ? 'Keep Sendix open to accept incoming transfers.'
                            : 'Try another activity filter.',
                        iconBuilder: _buildReceiveEmptyIcon,
                        showIconBackground: false,
                      ),
                    )
                  else
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i != 0) const SizedBox(height: 12),
                      transferCard(filtered[i]),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  DateTime? _startTimeFor(TransferProgress progress) {
    if (progress.direction == TransferDirection.receive) {
      return widget.controller.startTimeFor(progress.transferId);
    }
    return widget.outgoingStartTimeFor?.call(progress.transferId);
  }

  bool _matchesFilter(TransferProgress progress) {
    return switch (_activityFilter) {
      _ActivityFilter.all =>
        progress.direction == TransferDirection.receive ||
            progress.status == TransferStatus.failed,
      _ActivityFilter.received =>
        progress.direction == TransferDirection.receive,
      _ActivityFilter.failed => progress.status == TransferStatus.failed,
    };
  }
}

enum _ActivityFilter {
  all('All'),
  received('Received'),
  failed('Failed');

  const _ActivityFilter(this.label);

  final String label;
}
