import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/networking/device_identity.dart';
import 'package:sendix/features/receive/receive_settings_controller.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';
import 'package:sendix/ui/widgets/section_card.dart';
import 'package:sendix/ui/widgets/svg_icon.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.identity,
    required this.receiveSettingsController,
    required this.fileManager,
    this.showAppBar = true,
    this.desktopLayout = false,
  });

  final DeviceIdentity identity;
  final ReceiveSettingsController receiveSettingsController;
  final FileManager fileManager;
  final bool showAppBar;
  final bool desktopLayout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

const String _appVersionLabel = 'v2.17.4';
const String _developerName = 'Sachicodex';

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final Future<String> _defaultReceivePath = widget.fileManager
      .getDefaultReceiveDirectoryPath();
  bool _pickingFolder = false;
  late final TextEditingController _deviceNameController =
      TextEditingController(text: widget.identity.name);
  final TextEditingController _storagePathController = TextEditingController();
  bool _savingDeviceName = false;
  late final AnimationController _checkController;
  late final Animation<double> _checkTurns;
  late final Animation<double> _checkScale;
  late final Animation<Color?> _checkColor;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 420),
    );
    _checkTurns = Tween<double>(begin: 0.0, end: 0.045).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.easeOutBack),
    );
    _checkScale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.easeOutBack),
    );
    _checkColor =
        ColorTween(
          begin: AppColors.success,
          end: AppColors.primaryAccent,
        ).animate(
          CurvedAnimation(parent: _checkController, curve: Curves.easeOutCubic),
        );
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _storagePathController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  Future<void> _saveDeviceName() async {
    if (_savingDeviceName) return;
    setState(() => _savingDeviceName = true);
    try {
      final name = _deviceNameController.text.trim();
      if (name.isEmpty) return;
      await widget.identity.setName(name);
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _savingDeviceName = false);
    }
  }

  void _onCheckTap() {
    if (_savingDeviceName ||
        _checkController.isAnimating ||
        _deviceNameController.text.trim().isEmpty) {
      return;
    }
    _checkController.forward(from: 0).then((_) => _checkController.reverse());
    _saveDeviceName();
  }

  Future<void> _pickReceiveFolder() async {
    if (_pickingFolder) return;
    setState(() => _pickingFolder = true);
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (!mounted) return;
      if (dir == null || dir.trim().isEmpty) return;
      await widget.receiveSettingsController.setCustomSavePath(dir);
    } finally {
      if (mounted) {
        setState(() => _pickingFolder = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const fieldPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 14);
    final content = ListView(
      padding: EdgeInsets.fromLTRB(16, widget.desktopLayout ? 0 : 16, 16, 24),
      children: [
        SectionCard(
          title: 'Device name',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _deviceNameController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onCheckTap(),
                decoration: InputDecoration(
                  hintText: 'e.g. My Laptop',
                  isDense: true,
                  contentPadding: fieldPadding,
                  suffixIcon: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _onCheckTap,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AnimatedBuilder(
                          animation: _checkController,
                          builder: (context, _) {
                            return ScaleTransition(
                              scale: _checkScale,
                              child: RotationTransition(
                                turns: _checkTurns,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(100),
                                    color: _checkColor.value,
                                  ),
                                  child: Center(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        const Icon(
                                          Icons.check_sharp,
                                          size: 17,
                                          color: AppColors.surface,
                                        ),
                                        Transform.translate(
                                          offset: const Offset(0.5, 0.5),
                                          child: const Icon(
                                            Icons.check_sharp,
                                            size: 17,
                                            color: AppColors.surface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Storage',
          child: ValueListenableBuilder<String?>(
            valueListenable: widget.receiveSettingsController.customSavePath,
            builder: (context, customPath, _) {
              return FutureBuilder<String>(
                future: _defaultReceivePath,
                builder: (context, snapshot) {
                  final defaultPath = snapshot.data;
                  final effective =
                      (customPath == null || customPath.trim().isEmpty)
                      ? defaultPath
                      : customPath.trim();
                  final storageText = effective ?? 'Loading...';
                  if (_storagePathController.text != storageText) {
                    _storagePathController.text = storageText;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _storagePathController,
                        readOnly: true,
                        showCursor: false,
                        enableInteractiveSelection: true,
                        maxLines: 1,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: fieldPadding,
                        ),
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (defaultPath != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Default: $defaultPath',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _pickingFolder
                                ? null
                                : _pickReceiveFolder,
                            style: FilledButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(
                                color: AppColors.surfaceTertiary,
                                width: 1,
                              ),
                              backgroundColor: AppColors.surfaceSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const SvgIcon(
                              asset: 'assets/svg/Folder.svg',
                              color: AppColors.textPrimary,
                              size: 18,
                            ),
                            label: const Text('Change'),
                          ),
                          TextButton.icon(
                            onPressed: _pickingFolder
                                ? null
                                : () => widget.receiveSettingsController
                                      .setCustomSavePath(null),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text('Reset'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Receiving',
          child: ValueListenableBuilder<bool>(
            valueListenable:
                widget.receiveSettingsController.skipAcceptForFavourite,
            builder: (context, skipAccept, _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-accept favourites'),
                value: skipAccept,
                onChanged: (value) {
                  widget.receiveSettingsController.setSkipAcceptForFavourite(
                    value,
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'About',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: _AboutInfoCard(
                  label: 'Developer',
                  value: _developerName,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _AboutInfoCard(
                  label: 'App version',
                  value: _appVersionLabel,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final body = Stack(
      children: [
        content,
        if (_pickingFolder)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.background.withAlpha(0x88),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );

    if (!widget.showAppBar) return body;

    return Scaffold(body: body);
  }
}

class _AboutInfoCard extends StatelessWidget {
  const _AboutInfoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceTertiary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
