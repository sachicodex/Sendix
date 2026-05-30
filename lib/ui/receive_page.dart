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

class ReceivePage extends StatefulWidget {
  const ReceivePage({
    super.key,
    required this.controller,
    this.desktopLayout = false,
  });

  final ReceiveController controller;
  final bool desktopLayout;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final _speedTracker = TransferSpeedTracker();
  static const String _receiveLottieAsset = 'assets/lottie/Pulse.json';
  late final Future<ByteData> _receiveLottieData = rootBundle.load(
    _receiveLottieAsset,
  );

  bool _isMobileLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 520;

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

    final dir = File(filePath).parent.path;
    await OpenFilex.open(dir);
  }

  Future<void> _showTransferMenu(TransferProgress progress) async {
    final path = progress.localPath;
    final control = widget.controller.controlFor(progress.transferId);
    final isInProgress = progress.status == TransferStatus.inProgress;
    final paused = control?.paused.value ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
              children: [
                if (isInProgress) ...[
                  ListTile(
                    leading: Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: AppColors.textSecondary,
                    ),
                    title: Text(paused ? 'Resume' : 'Pause'),
                    enabled: control != null,
                    onTap: control == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
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
                  ListTile(
                    leading: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                    title: const Text('Cancel'),
                    enabled: control != null,
                    onTap: control == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            widget.controller.cancelTransfer(
                              progress.transferId,
                            );
                          },
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('Open location'),
                  enabled: path != null && path.trim().isNotEmpty,
                  onTap: (path == null || path.trim().isEmpty)
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          await _openLocation(path);
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete'),
                  enabled:
                      progress.status == TransferStatus.completed &&
                      path != null &&
                      path.trim().isNotEmpty,
                  onTap:
                      (progress.status != TransferStatus.completed ||
                          path == null ||
                          path.trim().isEmpty)
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          try {
                            await File(path).delete();
                          } catch (_) {}
                          widget.controller.dismissTransfer(
                            progress.transferId,
                          );
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<TransferProgress>>(
      valueListenable: widget.controller.transfers,
      builder: (context, transfers, _) {
        final ordered = List<TransferProgress>.from(transfers)
          ..sort((a, b) {
            final aStart =
                widget.controller
                    .startTimeFor(a.transferId)
                    ?.millisecondsSinceEpoch ??
                0;
            final bStart =
                widget.controller
                    .startTimeFor(b.transferId)
                    ?.millisecondsSinceEpoch ??
                0;
            if (aStart != bStart) return bStart.compareTo(aStart);
            return a.transferId.compareTo(b.transferId);
          });

        if (ordered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: EmptyState(
              title: 'Ready to receive',
              message: 'Keep Sendix open to accept incoming transfers.',
              iconBuilder: _buildReceiveEmptyIcon,
              showIconBackground: false,
            ),
          );
        }

        Widget header() {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
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
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget transferCard(TransferProgress progress) {
          final c = widget.controller.controlFor(progress.transferId);

          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showTransferMenu(progress),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: c == null
                    ? TransferProgressTile(
                        progress: progress,
                        speedBytesPerSecond: _speedTracker.update(progress),
                        showDirectionIcon: !_isMobileLayout(context),
                        isPaused: false,
                      )
                    : ValueListenableBuilder<bool>(
                        valueListenable: c.paused,
                        builder: (context, paused, _) {
                          return TransferProgressTile(
                            progress: progress,
                            speedBytesPerSecond: _speedTracker.update(progress),
                            showDirectionIcon: !_isMobileLayout(context),
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
                            onCancel:
                                progress.status == TransferStatus.inProgress
                                ? () => widget.controller.cancelTransfer(
                                    progress.transferId,
                                  )
                                : null,
                          );
                        },
                      ),
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
            header(),
            for (var i = 0; i < ordered.length; i++) ...[
              if (i != 0) const SizedBox(height: 12),
              transferCard(ordered[i]),
            ],
          ],
        );
      },
    );
  }
}
