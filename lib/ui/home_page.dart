import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/networking/transfer_control.dart';
import 'package:sendix/core/platform/share_receiver.dart';
import 'package:sendix/features/receive/receive_controller.dart';
import 'package:sendix/features/receive/receive_settings_controller.dart';
import 'package:sendix/features/send/send_controller.dart';
import 'package:sendix/models/transfer.dart';
import 'package:sendix/ui/receive_page.dart';
import 'package:sendix/ui/settings_page.dart';
import 'package:sendix/ui/send_page.dart';
import 'package:sendix/ui/splash_screen.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';
import 'package:sendix/ui/widgets/action_tile.dart';
import 'package:sendix/ui/widgets/svg_icon.dart';
import 'package:sendix/ui/widgets/transfer_speed_tracker.dart';
import 'package:window_manager/window_manager.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.sendController,
    required this.receiveController,
    required this.receiveSettingsController,
    required this.fileManager,
  });

  final SendController sendController;
  final ReceiveController receiveController;
  final ReceiveSettingsController receiveSettingsController;
  final FileManager fileManager;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  StreamSubscription<TransferRequest>? _requestSubscription;
  StreamSubscription<List<String>>? _shareSubscription;
  final ShareReceiver _shareReceiver = ShareReceiver();
  final ValueNotifier<List<TransferFile>> _sharedFiles =
      ValueNotifier<List<TransferFile>>([]);
  int _index = 0;
  late final PageController _pageController = PageController(initialPage: 0);
  final _sendOverlaySpeedTracker = TransferSpeedTracker();
  static const Duration _splashDuration = Duration(seconds: 2);
  Timer? _splashTimer;
  bool _splashVisible = true;
  int? _pendingIndex;
  int _splashSeed = 0;
  final Set<String> _completedSeen = {};
  Timer? _completionTimer;
  bool _completionVisible = false;
  int _completionSeed = 0;
  static const Duration _completionDuration = Duration(milliseconds: 1600);
  TransferDirection _completionDirection = TransferDirection.send;
  double _dragDx = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startServices());
    widget.sendController.transfers.addListener(_onSendTransfersChanged);
    widget.receiveController.transfers.addListener(_onReceiveTransfersChanged);

    _requestSubscription = widget.receiveController.incomingRequests.listen(
      _showRequestDialog,
    );

    unawaited(_shareReceiver.start());
    _shareSubscription = _shareReceiver.sharedPaths.listen(_handleSharedPaths);

    _startSplash();
  }

  Future<void> _startServices() async {
    try {
      await widget.receiveController.start();
      await widget.sendController.start();
      await widget.receiveSettingsController.start();
    } catch (error) {
      debugPrint('Failed to start Sendix services: $error');
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _requestSubscription?.cancel();
    _shareSubscription?.cancel();
    unawaited(_shareReceiver.dispose());
    _sharedFiles.dispose();
    _completionTimer?.cancel();
    _pageController.dispose();
    widget.sendController.transfers.removeListener(_onSendTransfersChanged);
    widget.receiveController.transfers.removeListener(
      _onReceiveTransfersChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.sendController.dispose());
    unawaited(widget.receiveController.dispose());
    unawaited(widget.receiveSettingsController.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.sendController.ensureDiscovery(broadcast: true));
    }
  }

  void _onSendTransfersChanged() {
    _handleCompleted(widget.sendController.transfers.value);
  }

  void _onReceiveTransfersChanged() {
    _handleCompleted(widget.receiveController.transfers.value);
  }

  void _handleCompleted(List<TransferProgress> list) {
    for (final t in list) {
      if (t.status == TransferStatus.completed &&
          !_completedSeen.contains(t.transferId)) {
        _completedSeen.add(t.transferId);
        _showCompletion(t.direction);
        break;
      }
    }
  }

  Future<void> _handleSharedPaths(List<String> paths) async {
    final files = await widget.fileManager.transferFilesFromPaths(paths);
    if (!mounted || files.isEmpty) return;
    _sharedFiles.value = files;
    _handleNavigation(0);
  }

  void _showCompletion(TransferDirection direction) {
    _completionTimer?.cancel();
    setState(() {
      _completionVisible = true;
      _completionSeed++;
      _completionDirection = direction;
    });
    _completionTimer = Timer(
      _completionDuration + const Duration(milliseconds: 200),
      () {
        if (!mounted) return;
        setState(() => _completionVisible = false);
      },
    );
  }

  Future<void> _showRequestDialog(TransferRequest request) async {
    if (!mounted) {
      request.respond(false);
      return;
    }

    final skipAccept =
        widget.receiveSettingsController.skipAcceptForFavourite.value;
    final favourites =
        widget.receiveSettingsController.favouriteDeviceIds.value;
    if (skipAccept && favourites.contains(request.from.id)) {
      _handleNavigation(1);
      request.respond(true);
      return;
    }

    final totalSize = _formatBytes(request.totalBytes);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final filesPreview = request.files.take(6).toList(growable: false);

        Widget statTile({
          required IconData icon,
          required String label,
          required String value,
        }) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceTertiary.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceSecondary),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primaryAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        Widget sectionBox({required String title, required Widget child}) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceTertiary.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.surfaceSecondary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.surfaceSecondary),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 30,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Incoming Transfer',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.titleLarge.copyWith(
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: statTile(
                            icon: Icons.insert_drive_file_rounded,
                            label: 'Files',
                            value: '${request.files.length}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: statTile(
                            icon: Icons.data_usage_rounded,
                            label: 'Total size',
                            value: totalSize,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<String>(
                      future: widget.fileManager
                          .getDefaultReceiveDirectoryPath(),
                      builder: (context, snapshot) {
                        final defaultPath = snapshot.data ?? 'Loading...';
                        final custom = widget
                            .receiveSettingsController
                            .customSavePath
                            .value;
                        final effective =
                            (custom == null || custom.trim().isEmpty)
                            ? defaultPath
                            : custom.trim();
                        return sectionBox(
                          title: 'Saving to',
                          child: Text(
                            effective,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    sectionBox(
                      title: 'Files name',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 168),
                        child: Scrollbar(
                          thumbVisibility: filesPreview.length > 3,
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount:
                                filesPreview.length +
                                (request.files.length > filesPreview.length
                                    ? 1
                                    : 0),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (index < filesPreview.length) {
                                final file = filesPreview[index];
                                return Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primaryAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        file.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                              color: AppColors.textPrimary,
                                            ),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Text(
                                '+ ${request.files.length - filesPreview.length} more file(s)',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 360;
                        final acceptButton = FilledButton(
                          onPressed: () {
                            _handleNavigation(1);
                            Navigator.of(context).pop(true);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryAccent,
                            foregroundColor: AppColors.background,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Accept'),
                        );
                        final rejectButton = OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Reject'),
                        );

                        if (stacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              acceptButton,
                              const SizedBox(height: 10),
                              rejectButton,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: rejectButton),
                            const SizedBox(width: 12),
                            Expanded(child: acceptButton),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    request.respond(approved ?? false);
  }

  void _startSplash({int? targetIndex}) {
    _splashTimer?.cancel();
    setState(() {
      _splashSeed++;
      if (targetIndex != null) {
        _pendingIndex = _clampIndex(targetIndex);
      }
      _splashVisible = true;
    });
    _splashTimer = Timer(_splashDuration, _completeSplash);
  }

  void _completeSplash() {
    if (!mounted) return;
    setState(() {
      if (_pendingIndex != null) {
        _index = _clampIndex(_pendingIndex!);
        _pendingIndex = null;
      }
      _splashVisible = false;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_index);
    }
  }

  void _handleNavigation(int index) {
    if (!mounted) return;
    final clamped = _clampIndex(index);
    if (clamped == _index && !_splashVisible) return;
    _startSplash(targetIndex: clamped);
  }

  int _clampIndex(int index) => index.clamp(0, 2);

  Widget _wrapWithSendOverlay(Widget child) {
    return ValueListenableBuilder<List<TransferProgress>>(
      valueListenable: widget.sendController.transfers,
      builder: (context, transfers, _) {
        final waitingOrActive = transfers
            .where(
              (t) =>
                  t.direction == TransferDirection.send &&
                  (t.status == TransferStatus.pending ||
                      t.status == TransferStatus.inProgress),
            )
            .toList(growable: false);
        if (waitingOrActive.isEmpty) return child;

        final latest = waitingOrActive.last;
        final control = widget.sendController.controlFor(latest.transferId);
        final isWaiting = latest.status == TransferStatus.pending;
        final speed = isWaiting
            ? null
            : _sendOverlaySpeedTracker.update(latest);
        final compactOverlay = MediaQuery.sizeOf(context).width < 700;

        return Stack(
          children: [
            child,
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.background.withAlpha(0x66),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compactOverlay ? 12 : 0,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: _SendTransferOverlayCard(
                            progress: latest,
                            control: control,
                            isWaiting: isWaiting,
                            speedBytesPerSecond: speed,
                            onPauseResume: control == null
                                ? null
                                : () {
                                    if (control.paused.value) {
                                      widget.sendController.resumeTransfer(
                                        latest.transferId,
                                      );
                                    } else {
                                      widget.sendController.pauseTransfer(
                                        latest.transferId,
                                      );
                                    }
                                  },
                            onCancel: control == null
                                ? null
                                : () => widget.sendController.cancelTransfer(
                                    latest.transferId,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _wrapWithSplashOverlay(Widget child) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_splashVisible,
            child: AnimatedOpacity(
              opacity: _splashVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOutCubic,
              child: SplashScreen(
                key: ValueKey<int>(_splashSeed),
                progressDuration: _splashDuration,
                animateIntro: false,
                showLoading: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _wrapWithCompletionOverlay(Widget child) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _completionVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: AppColors.background.withAlpha(0x66),
                    ),
                  ),
                  Center(
                    child: AnimatedScale(
                      scale: _completionVisible ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      child: _CompletionBadge(
                        playToken: _completionSeed,
                        direction: _completionDirection,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final windowsDesktop =
            desktop && defaultTargetPlatform == TargetPlatform.windows;
        final navSelected = AppColors.primaryAccent;
        final navUnselected = AppColors.textTertiary;

        Widget navSvg(String asset, Color color) {
          return SizedBox(
            width: 20,
            height: 20,
            child: SvgIcon(asset: asset, color: color, size: 20),
          );
        }

        if (desktop) {
          final pages = [
            SendPage(
              controller: widget.sendController,
              receiveSettingsController: widget.receiveSettingsController,
              fileManager: widget.fileManager,
              sharedFiles: _sharedFiles,
              desktopLayout: true,
            ),
            ReceivePage(
              controller: widget.receiveController,
              desktopLayout: true,
            ),
            SettingsPage(
              identity: widget.sendController.identity,
              receiveSettingsController: widget.receiveSettingsController,
              fileManager: widget.fileManager,
              desktopLayout: true,
            ),
          ];
          final safeIndex = _index.clamp(0, pages.length - 1);

          Widget navItem({
            required int index,
            required IconData icon,
            required String label,
            Widget? iconWidget,
          }) {
            final selected = safeIndex == index;
            final iconColor = selected ? navSelected : navUnselected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActionTile(
                icon: icon,
                iconWidget: iconWidget,
                iconColor: iconWidget == null ? iconColor : null,
                label: label,
                labelColor: selected ? navSelected : navUnselected,
                selected: false,
                showIconBackground: false,
                onTap: () => _handleNavigation(index),
              ),
            );
          }

          final shell = Scaffold(
            body: Column(
              children: [
                if (windowsDesktop) const _WindowsTitleBar(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      children: [
                        SafeArea(
                          top: !windowsDesktop,
                          child: Container(
                            width: 260,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.surfaceSecondary,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 18,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  20,
                                  18,
                                  18,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ListView(
                                        padding: const EdgeInsets.only(top: 6),
                                        children: [
                                          navItem(
                                            index: 0,
                                            icon: Icons.send_rounded,
                                            iconWidget: navSvg(
                                              'assets/svg/send.svg',
                                              safeIndex == 0
                                                  ? navSelected
                                                  : navUnselected,
                                            ),
                                            label: 'Send',
                                          ),
                                          navItem(
                                            index: 1,
                                            icon: Icons.home,
                                            iconWidget: navSvg(
                                              'assets/svg/receive.svg',
                                              safeIndex == 1
                                                  ? navSelected
                                                  : navUnselected,
                                            ),
                                            label: 'Receive',
                                          ),
                                          navItem(
                                            index: 2,
                                            icon: Icons.settings_outlined,
                                            iconWidget: navSvg(
                                              'assets/svg/setting.svg',
                                              safeIndex == 2
                                                  ? navSelected
                                                  : navUnselected,
                                            ),
                                            label: 'Settings',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SafeArea(
                            top: !windowsDesktop,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: IndexedStack(
                                index: safeIndex,
                                children: pages,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
          return _wrapWithCompletionOverlay(
            _wrapWithSplashOverlay(_wrapWithSendOverlay(shell)),
          );
        }

        final shell = Scaffold(
          appBar: AppBar(
            title: Text(
              'SENDIX',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.primaryAccent,
                fontSize: 20,
                letterSpacing: 1.05,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _dragDx = 0.0,
              onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
              onHorizontalDragEnd: (details) {
                if (_splashVisible) return;
                final velocity = details.velocity.pixelsPerSecond.dx;
                final delta = _dragDx;
                if (velocity.abs() > 300) {
                  _handleNavigation(_index + (velocity < 0 ? 1 : -1));
                  return;
                }
                if (delta.abs() > 60) {
                  _handleNavigation(_index + (delta < 0 ? 1 : -1));
                }
              },
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  if (!mounted) return;
                  setState(() => _index = _clampIndex(index));
                },
                children: [
                  SendPage(
                    controller: widget.sendController,
                    receiveSettingsController: widget.receiveSettingsController,
                    fileManager: widget.fileManager,
                    sharedFiles: _sharedFiles,
                    desktopLayout: false,
                  ),
                  ReceivePage(
                    controller: widget.receiveController,
                    desktopLayout: false,
                  ),
                  SettingsPage(
                    identity: widget.sendController.identity,
                    receiveSettingsController: widget.receiveSettingsController,
                    fileManager: widget.fileManager,
                    showAppBar: false,
                    desktopLayout: false,
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.surfaceSecondary),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index.clamp(0, 2),
              onDestinationSelected: (index) {
                _handleNavigation(index);
              },
              destinations: [
                NavigationDestination(
                  icon: navSvg('assets/svg/send.svg', navUnselected),
                  selectedIcon: navSvg('assets/svg/send.svg', navSelected),
                  label: 'Send',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: navSvg('assets/svg/receive.svg', navUnselected),
                  selectedIcon: navSvg('assets/svg/receive.svg', navSelected),
                  label: 'Receive',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: navSvg('assets/svg/setting.svg', navUnselected),
                  selectedIcon: navSvg('assets/svg/setting.svg', navSelected),
                  label: 'Settings',
                  tooltip: '',
                ),
              ],
            ),
          ),
        );
        return _wrapWithCompletionOverlay(
          _wrapWithSplashOverlay(_wrapWithSendOverlay(shell)),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}

class _SendTransferOverlayCard extends StatelessWidget {
  const _SendTransferOverlayCard({
    required this.progress,
    required this.control,
    required this.isWaiting,
    required this.speedBytesPerSecond,
    required this.onPauseResume,
    required this.onCancel,
  });

  final TransferProgress progress;
  final TransferControl? control;
  final bool isWaiting;
  final double? speedBytesPerSecond;
  final VoidCallback? onPauseResume;
  final VoidCallback? onCancel;

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final paused = control?.paused.value ?? false;
    final statusColor = isWaiting
        ? AppColors.textPrimary
        : paused
        ? AppColors.textSecondary
        : AppColors.success;
    final statusLabel = isWaiting
        ? 'Pending approval'
        : paused
        ? 'Paused'
        : 'Sending';
    final sizeText = _formatBytes(progress.totalBytes);
    final speedText = speedBytesPerSecond == null || speedBytesPerSecond! <= 0
        ? 'Waiting'
        : '${_formatBytes(speedBytesPerSecond!.round())}/s';
    final actionLabel = isWaiting
        ? 'You can cancel while waiting.'
        : paused
        ? 'Tap resume to continue.'
        : 'Tap pause if you need to stop for a moment.';

    Widget summaryRow({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceTertiary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceSecondary),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: statusColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            statusLabel,
            style: AppTextStyles.bodySmall.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 18),
        summaryRow(
          icon: Icons.insert_drive_file_rounded,
          label: 'File',
          value: progress.fileName,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: summaryRow(
                icon: Icons.data_usage_rounded,
                label: 'Size',
                value: sizeText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: summaryRow(
                icon: Icons.speed_rounded,
                label: isWaiting ? 'Status' : 'Speed',
                value: speedText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: isWaiting ? null : progress.progress.clamp(0.0, 1.0),
            backgroundColor: AppColors.surfaceTertiary,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.primaryAccent,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          actionLabel,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (onPauseResume != null && !isWaiting) ...[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPauseResume,
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  ),
                  label: Text(paused ? 'Resume' : 'Pause'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WindowsTitleBar extends StatefulWidget {
  const _WindowsTitleBar();

  @override
  State<_WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<_WindowsTitleBar>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _syncMaximizedState();

  @override
  void onWindowUnmaximize() => _syncMaximizedState();

  Future<void> _syncMaximizedState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncMaximizedState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(14, 7, 18, 5),
      color: AppColors.background,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceSecondary),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/Logo/Sendix.png',
                      width: 20,
                      height: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Sendix',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _TitleWindowButton(
            icon: Icons.remove_rounded,
            iconColor: AppColors.textTertiary,
            hoverIconColor: AppColors.textPrimary,
            hoverColor: AppColors.surfaceSecondary.withValues(alpha: 0.92),
            hoverBorderColor: AppColors.surfaceSecondary,
            onPressed: windowManager.minimize,
          ),
          const SizedBox(width: 8),
          _TitleWindowButton(
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconColor: AppColors.textTertiary,
            hoverIconColor: AppColors.textPrimary,
            hoverColor: AppColors.surfaceSecondary.withValues(alpha: 0.92),
            hoverBorderColor: AppColors.surfaceSecondary,
            onPressed: _toggleMaximize,
          ),
          const SizedBox(width: 8),
          _TitleWindowButton(
            icon: Icons.close_rounded,
            backgroundColor: AppColors.danger.withValues(alpha: 0.1),
            borderColor: const Color(0xFF32180F),
            hoverColor: AppColors.danger.withValues(alpha: 0.3),
            onPressed: windowManager.close,
          ),
        ],
      ),
    );
  }
}

class _TitleWindowButton extends StatefulWidget {
  const _TitleWindowButton({
    required this.icon,
    required this.onPressed,
    this.backgroundColor = AppColors.surface,
    this.borderColor = AppColors.surfaceSecondary,
    this.hoverColor = AppColors.surfaceSecondary,
    this.hoverBorderColor,
    this.iconColor = AppColors.textTertiary,
    this.hoverIconColor = AppColors.textPrimary,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color borderColor;
  final Color hoverColor;
  final Color? hoverBorderColor;
  final Color iconColor;
  final Color hoverIconColor;

  @override
  State<_TitleWindowButton> createState() => _TitleWindowButtonState();
}

class _TitleWindowButtonState extends State<_TitleWindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 50,
          height: 44,
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : widget.backgroundColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _hovered
                  ? widget.hoverBorderColor ??
                        AppColors.textTertiary.withValues(alpha: 0.16)
                  : widget.borderColor,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            scale: _hovered ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: widget.iconColor,
                end: _hovered ? widget.hoverIconColor : widget.iconColor,
              ),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              builder: (context, color, child) {
                return IconTheme(
                  data: IconThemeData(color: color),
                  child: child!,
                );
              },
              child: Icon(widget.icon, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionBadge extends StatefulWidget {
  const _CompletionBadge({required this.playToken, required this.direction});

  final int playToken;
  final TransferDirection direction;

  @override
  State<_CompletionBadge> createState() => _CompletionBadgeState();
}

class _CompletionBadgeState extends State<_CompletionBadge>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 1600);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.playToken != 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _CompletionBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playToken != widget.playToken) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _interval(double t, double start, double end) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return (t - start) / (end - start);
  }

  @override
  Widget build(BuildContext context) {
    final isSend = widget.direction == TransferDirection.send;
    final accent = AppColors.success;
    final highlight = Color.lerp(accent, Colors.white, 0.35) ?? accent;
    final title = isSend ? 'Sent successfully' : 'Received successfully';
    final subtitle = 'Transfer complete';

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final popT = Curves.easeOutCubic.transform(_interval(t, 0.0, 0.55));
            final fadeT = Curves.easeOutCubic.transform(_interval(t, 0.0, 0.2));
            final iconT = Curves.easeOutCubic.transform(_interval(t, 0.1, 0.6));
            final textT = Curves.easeOutCubic.transform(
              _interval(t, 0.22, 0.85),
            );

            final scale = lerpDouble(0.96, 1.0, popT) ?? 1.0;
            final iconScale = lerpDouble(0.88, 1.0, iconT) ?? 1.0;

            return Opacity(
              opacity: fadeT,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 22,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.35),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 16,
                        spreadRadius: -2,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: iconScale,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.2, -0.2),
                              radius: 0.9,
                              colors: [
                                highlight.withValues(alpha: 0.6),
                                accent.withValues(alpha: 0.4),
                              ],
                            ),
                            border: Border.all(
                              color: highlight.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 30,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Opacity(
                        opacity: textT,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: AppTextStyles.titleMedium.copyWith(
                                color: Colors.white.withValues(alpha: 0.96),
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                                letterSpacing: 0.2,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.9,
                                ),
                                fontSize: 13,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
