import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/platform/installed_apps.dart';
import 'package:sendix/features/receive/receive_settings_controller.dart';
import 'package:sendix/features/send/send_controller.dart';
import 'package:sendix/models/device.dart';
import 'package:sendix/models/transfer.dart';
import 'package:sendix/ui/theme/app_card_theme.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';
import 'package:sendix/ui/widgets/app_snackbar.dart';
import 'package:sendix/ui/widgets/empty_state.dart';
import 'package:sendix/ui/widgets/section_card.dart';
import 'package:sendix/ui/widgets/action_tile.dart';
import 'package:sendix/ui/widgets/svg_icon.dart';

class SendPage extends StatefulWidget {
  const SendPage({
    super.key,
    required this.controller,
    required this.receiveSettingsController,
    required this.fileManager,
    required this.sharedFiles,
    this.desktopLayout = false,
  });

  final SendController controller;
  final ReceiveSettingsController receiveSettingsController;
  final FileManager fileManager;
  final ValueNotifier<List<TransferFile>> sharedFiles;
  final bool desktopLayout;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  DeviceInfo? _selectedDevice;
  List<TransferFile> _selectedFiles = [];
  bool _sending = false;
  bool _draggingSelection = false;
  String? _lastAutoSendKey;
  bool _refreshingDevices = false;
  String? _lastSharedKey;
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  @override
  void initState() {
    super.initState();
    widget.sharedFiles.addListener(_onSharedFilesChanged);
    _applySharedFiles(widget.sharedFiles.value);
  }

  @override
  void didUpdateWidget(covariant SendPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedFiles != widget.sharedFiles) {
      oldWidget.sharedFiles.removeListener(_onSharedFilesChanged);
      widget.sharedFiles.addListener(_onSharedFilesChanged);
      _applySharedFiles(widget.sharedFiles.value);
    }
  }

  @override
  void dispose() {
    widget.sharedFiles.removeListener(_onSharedFilesChanged);
    _scrollController.dispose();
    super.dispose();
  }

  int get _totalSelectedBytes =>
      _selectedFiles.fold<int>(0, (sum, f) => sum + f.size);

  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _isWindowsPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _useMobileQuickAdd(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return _isMobilePlatform || width < 520;
  }

  void _addSelectedFiles(List<TransferFile> files) {
    if (files.isEmpty) return;
    final current = List<TransferFile>.from(_selectedFiles);
    final existing = current
        .map((f) => f.absolutePath ?? f.relativePath)
        .toSet();
    for (final f in files) {
      final key = f.absolutePath ?? f.relativePath;
      if (existing.add(key)) {
        current.add(f);
      }
    }
    setState(() => _selectedFiles = current);
  }

  void _setSelectedFiles(List<TransferFile> files) {
    setState(() {
      _selectedFiles = files;
      if (files.isEmpty) {
        _selectedDevice = null;
      }
    });
    _lastAutoSendKey = null;
  }

  IconData _iconFor(TransferFile file) {
    final ext = p.extension(file.absolutePath ?? file.name).toLowerCase();
    switch (ext) {
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.webp':
      case '.gif':
      case '.bmp':
        return Icons.image_rounded;
      case '.txt':
      case '.md':
      case '.json':
      case '.xml':
      case '.yaml':
      case '.yml':
        return Icons.text_snippet_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _pickFiles() async {
    final files = await widget.controller.pickFiles();
    if (!mounted) return;
    _setSelectedFiles(files);
    _maybeAutoSend();
  }

  Future<void> _pickDirectory() async {
    final files = await widget.controller.pickDirectory();
    if (!mounted) return;
    _setSelectedFiles(files);
    _maybeAutoSend();
  }

  Future<void> _pickImages() async {
    if (_sending) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>();
    final files = await widget.fileManager.transferFilesFromPaths(paths);
    if (!mounted) return;
    _addSelectedFiles(files);
    _maybeAutoSend();
  }

  Future<void> _pickAppFiles() async {
    if (_sending) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['apk', 'aab', 'ipa'],
    );
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>();
    final files = await widget.fileManager.transferFilesFromPaths(paths);
    if (!mounted) return;
    _addSelectedFiles(files);
    _maybeAutoSend();
  }

  Future<void> _showInstalledAppsSheet() async {
    if (_sending || !_isAndroidPlatform) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: _InstalledAppsSheet(
              onPick: (app) async {
                Navigator.of(context).pop();
                await _addInstalledApp(app);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _addInstalledApp(InstalledAppInfo app) async {
    if (!_isAndroidPlatform) return;

    try {
      final srcPath = app.apkPath;
      final src = File(srcPath);
      final exists = await src.exists();
      if (!exists) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'Could not read app package.',
          type: AppSnackBarType.error,
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeName = app.appName
          .replaceAll(RegExp(r'[\\\\/:*?\"<>|]+'), '_')
          .trim()
          .replaceAll('  ', ' ');
      final outPath = p.join(
        dir.path,
        'sendix_app_${app.packageName}_$stamp.apk',
      );
      await src.copy(outPath);

      final files = await widget.fileManager.transferFilesFromPaths([outPath]);
      if (!mounted) return;
      _addSelectedFiles(
        files
            .map(
              (f) => TransferFile(
                name: '$safeName.apk',
                relativePath: '$safeName.apk',
                size: f.size,
                absolutePath: f.absolutePath,
              ),
            )
            .toList(growable: false),
      );
      _maybeAutoSend();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Failed to add app: $error',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _sendText() async {
    if (_sending) return;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send text'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 680),
            child: TextField(
              controller: controller,
              minLines: 10,
              maxLines: 15,
              decoration: const InputDecoration(
                hintText: 'Type text to send...',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    final normalized = (text ?? '').trim();
    if (!mounted || normalized.isEmpty) return;
    await _addTextAsFile(normalized);
  }

  Future<void> _addTextAsFile(String text) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final path = p.join(dir.path, 'sendix_text_$stamp.txt');
    await File(path).writeAsString(text, flush: true);

    final files = await widget.fileManager.transferFilesFromPaths([path]);
    if (!mounted) return;
    _addSelectedFiles(files);
    _maybeAutoSend();
  }

  Future<void> _pasteClipboard() async {
    if (_sending) return;

    final uriData = _isWindowsPlatform
        ? await _safeClipboardGet('text/uri-list')
        : null;
    final textData = await _safeClipboardGet(Clipboard.kTextPlain);
    final plainTextData = await _safeClipboardGet('text/plain');
    final utf8TextData = await _safeClipboardGet('text/plain;charset=utf-8');

    final paths = <String>[];
    final uriText = uriData?.text?.trim();
    if (uriText != null && uriText.isNotEmpty) {
      for (final line in uriText.split(RegExp(r'[\r\n]+'))) {
        final entry = line.trim();
        if (entry.isEmpty || entry.startsWith('#')) continue;
        final uri = Uri.tryParse(entry);
        if (uri != null && uri.scheme == 'file') {
          paths.add(uri.toFilePath());
        } else {
          paths.add(entry);
        }
      }
    }

    if (paths.isNotEmpty) {
      final files = await widget.fileManager.transferFilesFromPaths(paths);
      if (!mounted) return;
      if (files.isNotEmpty) {
        _addSelectedFiles(files);
        _maybeAutoSend();
        return;
      }
    }

    var text = textData?.text?.trim() ?? '';
    if (text.isEmpty) {
      text = plainTextData?.text?.trim() ?? '';
    }
    if (text.isEmpty) {
      text = utf8TextData?.text?.trim() ?? '';
    }
    if (text.isEmpty && uriText != null && uriText.isNotEmpty) {
      text = uriText;
    }
    if (text.isEmpty) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'You can only paste text.',
        type: AppSnackBarType.info,
      );
      return;
    }

    if (File(text).existsSync() || Directory(text).existsSync()) {
      final files = await widget.fileManager.transferFilesFromPaths([text]);
      if (!mounted) return;
      if (files.isNotEmpty) {
        _addSelectedFiles(files);
        _maybeAutoSend();
        return;
      }
    }

    await _addTextAsFile(text);
  }

  Future<ClipboardData?> _safeClipboardGet(String format) async {
    try {
      return await Clipboard.getData(format);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleDroppedPaths(Iterable<String> paths) async {
    if (_sending) return;
    final dropped = await widget.fileManager.transferFilesFromPaths(paths);
    if (!mounted) return;
    _addSelectedFiles(dropped);
    _maybeAutoSend();
  }

  Future<void> _showPreview(TransferFile file) async {
    if (!mounted) return;
    final path = file.absolutePath;
    if (path == null || path.trim().isEmpty) {
      showAppSnackBar(
        context,
        'Preview not available.',
        type: AppSnackBarType.info,
      );
      return;
    }

    final ext = p.extension(path).toLowerCase();
    final isImage = {
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
      '.bmp',
    }.contains(ext);
    final isText = {
      '.txt',
      '.md',
      '.json',
      '.xml',
      '.yaml',
      '.yml',
    }.contains(ext);

    if (isImage) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  minScale: 0.6,
                  maxScale: 4,
                  child: Image.file(File(path), fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    if (isText) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleSmall,
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
              child: FutureBuilder<String>(
                future: File(path).readAsString(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Text('Failed to load preview.');
                  }
                  final text = snapshot.data ?? '';
                  return SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(file.name),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Size: ${_formatBytes(file.size)}'),
                const SizedBox(height: 8),
                Text(
                  path,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _onSharedFilesChanged() {
    _applySharedFiles(widget.sharedFiles.value);
  }

  void _applySharedFiles(List<TransferFile> files) {
    if (files.isEmpty) return;
    final key =
        files
            .map(
              (f) =>
                  '${f.absolutePath ?? f.relativePath}:${f.size}:${f.relativePath}',
            )
            .toList(growable: false)
          ..sort();
    final joined = key.join('|');
    if (joined == _lastSharedKey) return;
    _lastSharedKey = joined;
    _setSelectedFiles(files);
    _maybeAutoSend();
    widget.sharedFiles.value = const [];
  }

  String? _computeSelectionKey() {
    final device = _selectedDevice;
    if (device == null || _selectedFiles.isEmpty) return null;

    final items =
        _selectedFiles
            .map(
              (f) =>
                  '${f.absolutePath ?? f.relativePath}:${f.size}:${f.relativePath}',
            )
            .toList(growable: false)
          ..sort();
    return '${device.id}|${items.join('|')}';
  }

  void _maybeAutoSend() {
    if (_sending) return;
    final key = _computeSelectionKey();
    if (key == null) {
      _lastAutoSendKey = null;
      return;
    }
    if (key == _lastAutoSendKey) return;
    _lastAutoSendKey = key;
    unawaited(_send());
  }

  Future<void> _send() async {
    if (_sending || _selectedDevice == null || _selectedFiles.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.controller.sendFiles(_selectedDevice!, _selectedFiles);
      if (!mounted) return;
      _setSelectedFiles(const []);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Send failed: $error',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshNearbyDevices() async {
    if (_refreshingDevices || _sending) return;
    setState(() => _refreshingDevices = true);
    try {
      await widget.controller.refreshDevices();
    } finally {
      if (mounted) setState(() => _refreshingDevices = false);
    }
  }

  List<_QuickAddTile> _quickAddTiles({required bool mobileOnly}) {
    Widget svgIcon(String asset, Color color) {
      return SvgIcon(asset: asset, color: color, size: 22);
    }

    final iconFg = AppColors.textPrimary;

    if (mobileOnly) {
      if (_isWindowsPlatform) {
        return [
          _QuickAddTile(
            icon: Icons.insert_drive_file_rounded,
            iconWidget: svgIcon('assets/svg/file.svg', iconFg),
            label: 'File',
            onTap: _pickFiles,
          ),
          _QuickAddTile(
            icon: Icons.folder_open_rounded,
            iconWidget: svgIcon('assets/svg/Folder.svg', iconFg),
            label: 'Folder',
            onTap: _pickDirectory,
          ),
          _QuickAddTile(
            icon: Icons.image_rounded,
            iconWidget: svgIcon('assets/svg/image.svg', iconFg),
            label: 'Image',
            onTap: _pickImages,
          ),
          _QuickAddTile(
            icon: Icons.content_paste_rounded,
            iconWidget: svgIcon('assets/svg/paste.svg', iconFg),
            label: 'Paste',
            onTap: _pasteClipboard,
          ),
        ];
      }

      return [
        _QuickAddTile(
          icon: Icons.insert_drive_file_rounded,
          iconWidget: svgIcon('assets/svg/file.svg', iconFg),
          label: 'File',
          onTap: _pickFiles,
        ),
        _QuickAddTile(
          icon: Icons.image_rounded,
          iconWidget: svgIcon('assets/svg/image.svg', iconFg),
          label: 'Image',
          onTap: _pickImages,
        ),
        _QuickAddTile(
          icon: Icons.insert_drive_file_rounded,
          iconWidget: svgIcon('assets/svg/app.svg', iconFg),
          label: 'App',
          onTap: _isAndroidPlatform ? _showInstalledAppsSheet : _pickAppFiles,
        ),
        _QuickAddTile(
          icon: Icons.content_paste_rounded,
          iconWidget: svgIcon('assets/svg/paste.svg', iconFg),
          label: 'Paste',
          onTap: _pasteClipboard,
        ),
      ];
    }

    final tiles = <_QuickAddTile>[
      _QuickAddTile(
        icon: Icons.insert_drive_file_rounded,
        iconWidget: svgIcon('assets/svg/file.svg', iconFg),
        label: 'File',
        onTap: _pickFiles,
      ),
      _QuickAddTile(
        icon: Icons.folder_open_rounded,
        iconWidget: svgIcon('assets/svg/Folder.svg', iconFg),
        label: 'Folder',
        onTap: _pickDirectory,
      ),
      _QuickAddTile(
        icon: Icons.image_rounded,
        iconWidget: svgIcon('assets/svg/image.svg', iconFg),
        label: 'Images',
        onTap: _pickImages,
      ),
      _QuickAddTile(
        icon: Icons.text_fields_rounded,
        iconWidget: svgIcon('assets/svg/text.svg', iconFg),
        label: 'Text',
        onTap: _sendText,
      ),
    ];

    if (!_isWindowsPlatform) {
      tiles.add(
        _QuickAddTile(
          icon: Icons.insert_drive_file_rounded,
          iconWidget: svgIcon('assets/svg/app.svg', iconFg),
          label: 'App',
          onTap: _isAndroidPlatform ? _showInstalledAppsSheet : _pickAppFiles,
        ),
      );
    }

    return tiles;
  }

  Widget _quickAddGrid({required bool compact}) {
    final mobileQuickAdd = _useMobileQuickAdd(context);
    final tiles = _quickAddTiles(mobileOnly: mobileQuickAdd);

    if (mobileQuickAdd) {
      return SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tiles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            return SizedBox(width: 108, child: tiles[index]);
          },
        ),
      );
    }

    if (compact) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: tiles
            .map((t) => SizedBox(width: 92, child: t))
            .toList(growable: false),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: tiles
          .map((t) => SizedBox(width: 108, child: t))
          .toList(growable: false),
    );
  }

  Future<void> _showAddSheet() async {
    if (_sending) return;
    final sheetWidth = MediaQuery.sizeOf(context).width;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints.tightFor(width: sheetWidth),
      builder: (context) {
        final tiles = _quickAddTiles(mobileOnly: _useMobileQuickAdd(context));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'What you want to send?',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: tiles
                      .map((t) => SizedBox(width: 108, child: t))
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectionCard(BuildContext context) {
    final filesCount = _selectedFiles.length;
    final sizeText = _formatBytes(_totalSelectedBytes);
    final mobileQuickAdd = _useMobileQuickAdd(context);

    Widget buildFileTile(int fileIndex) {
      final f = _selectedFiles[fileIndex];
      void removeThis() {
        final next = List<TransferFile>.from(_selectedFiles)
          ..removeAt(fileIndex);
        _setSelectedFiles(next);
      }

      final path = f.absolutePath;
      final ext = p.extension(path ?? f.name).toLowerCase();
      final isImage = {
        '.png',
        '.jpg',
        '.jpeg',
        '.webp',
        '.gif',
        '.bmp',
      }.contains(ext);
      final isApp = {'.apk', '.aab', '.ipa'}.contains(ext);

      Widget content;
      if (isImage && path != null) {
        content = ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(path),
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) {
              return Icon(
                Icons.image_rounded,
                size: 24,
                color: AppColors.primaryAccent,
              );
            },
          ),
        );
      } else if (isApp) {
        content = SvgIcon(
          asset: 'assets/svg/app.svg',
          color: AppColors.primaryAccent,
          size: 24,
        );
      } else {
        content = Icon(_iconFor(f), size: 24, color: AppColors.primaryAccent);
      }

      return Tooltip(
        message: f.relativePath,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _sending ? null : () => _showPreview(f),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceTertiary),
                color: AppCardTheme.base.surfaceSecondary,
              ),
              alignment: Alignment.center,
              child: Stack(
                children: [
                  Center(child: content),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: AppCardTheme.base.surfaceSecondary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending ? null : removeThis,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final card = SectionCard(
      title: 'What to send',
      subtitle: filesCount == 0
          ? 'Start with files or text.'
          : 'Ready to send.',
      trailing: _InfoChip(label: 'Items', value: '$filesCount'),
      subtitleTrailing: _InfoChip(label: 'Size', value: sizeText),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(fade);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: Container(
          key: ValueKey<int>(_selectedFiles.length),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectedFiles.isEmpty)
                        _quickAddGrid(compact: compact),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              if (_selectedFiles.isEmpty) ...[
                if (!mobileQuickAdd)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _sending ? null : _pickFiles,
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.surfaceTertiary.withAlpha(170),
                          ),
                          color: AppCardTheme.base.surface,
                        ),
                        child: const EmptyState(
                          title: 'Drop files here',
                          message: 'Or use the buttons above.',
                          icon: Icons.cloud_upload_rounded,
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                if (mobileQuickAdd)
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedFiles.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _AddMoreTile(
                            enabled: !_sending,
                            onTap: _showAddSheet,
                          );
                        }
                        return buildFileTile(index - 1);
                      },
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const tile = 72.0;
                      const spacing = 10.0;
                      const maxRows = 3;
                      final cols =
                          ((constraints.maxWidth + spacing) / (tile + spacing))
                              .floor()
                              .clamp(1, 99);
                      final itemCount = _selectedFiles.length + 1;
                      final rows = (itemCount / cols).ceil().clamp(1, 999);
                      final visibleRows = rows > maxRows ? maxRows : rows;
                      final height =
                          visibleRows * tile + (visibleRows - 1) * spacing;

                      return SizedBox(
                        height: height,
                        child: GridView.builder(
                          primary: false,
                          physics: rows > maxRows
                              ? const ClampingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                mainAxisExtent: tile,
                              ),
                          itemCount: itemCount,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _AddMoreTile(
                                enabled: !_sending,
                                onTap: _showAddSheet,
                              );
                            }
                            return buildFileTile(index - 1);
                          },
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: AppCardTheme.base.radius,
        child: Stack(
          children: [
            DropTarget(
              enable: !_sending,
              onDragEntered: (_) => setState(() => _draggingSelection = true),
              onDragExited: (_) => setState(() => _draggingSelection = false),
              onDragDone: (details) {
                setState(() => _draggingSelection = false);
                final paths = details.files
                    .map((f) => f.path)
                    .where((p) => p.trim().isNotEmpty);
                unawaited(_handleDroppedPaths(paths));
              },
              child: card,
            ),
            if (_draggingSelection)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppCardTheme.base.radius,
                      border: Border.all(
                        color: AppColors.primaryAccent,
                        width: 2,
                      ),
                      color: AppColors.surfaceTertiary,
                    ),
                    child: Center(
                      child: Text(
                        'Drop to add',
                        style: AppTextStyles.titleSmall,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devicesPane = AnimatedSize(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: _DevicesPane(
        selected: _selectedDevice,
        stream: widget.controller.devices,
        enabled: !_sending,
        canSelect: !_sending && _selectedFiles.isNotEmpty,
        refreshing: _refreshingDevices,
        onRefresh: _refreshNearbyDevices,
        onSelected: (d) {
          setState(() => _selectedDevice = d);
          _maybeAutoSend();
        },
        onSelectionInvalidated: () {
          setState(() => _selectedDevice = null);
          _lastAutoSendKey = null;
        },
        favouriteDeviceIds: widget.receiveSettingsController.favouriteDeviceIds,
        onToggleFavourite: widget.receiveSettingsController.toggleFavourite,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final selectionCard = _buildSelectionCard(context);

        Widget content;
        if (!wide) {
          content = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.desktopLayout ? 0 : 16,
                  16,
                  96,
                ),
                children: [
                  selectionCard,
                  const SizedBox(height: 12),
                  devicesPane,
                ],
              ),
            ),
          );
        } else {
          content = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  18,
                  widget.desktopLayout ? 0 : 16,
                  18,
                  96,
                ),
                children: [
                  selectionCard,
                  const SizedBox(height: 12),
                  devicesPane,
                ],
              ),
            ),
          );
        }

        return Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV):
                _PasteIntent(),
            LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyV):
                _PasteIntent(),
          },
          child: Actions(
            actions: {
              _PasteIntent: CallbackAction<_PasteIntent>(
                onInvoke: (_) {
                  _pasteClipboard();
                  return null;
                },
              ),
            },
            child: Focus(autofocus: true, child: content),
          ),
        );
      },
    );
  }
}

class _PasteIntent extends Intent {
  const _PasteIntent();
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

class _DevicesPane extends StatelessWidget {
  const _DevicesPane({
    required this.selected,
    required this.stream,
    required this.enabled,
    required this.canSelect,
    required this.refreshing,
    required this.onRefresh,
    required this.onSelected,
    required this.onSelectionInvalidated,
    required this.favouriteDeviceIds,
    required this.onToggleFavourite,
  });

  final DeviceInfo? selected;
  final Stream<List<DeviceInfo>> stream;
  final bool enabled;
  final bool canSelect;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final ValueChanged<DeviceInfo?> onSelected;
  final VoidCallback onSelectionInvalidated;
  final ValueListenable<List<String>> favouriteDeviceIds;
  final ValueChanged<String> onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Where to send',
      subtitle: canSelect ? 'Choose a nearby device.' : 'Add items first.',
      trailing: _RefreshIconButton(
        enabled: enabled,
        refreshing: refreshing,
        onPressed: onRefresh,
      ),
      child: StreamBuilder<List<DeviceInfo>>(
        stream: stream,
        builder: (context, snapshot) {
          final devices = snapshot.data ?? const <DeviceInfo>[];
          if (selected != null && !devices.contains(selected)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onSelectionInvalidated();
            });
          }

          if (devices.isEmpty) {
            return const EmptyState(
              title: 'No devices',
              message: 'Turn on Wi-Fi on both devices and keep Sendix open.',
              icon: Icons.devices,
            );
          }

          return ValueListenableBuilder<List<String>>(
            valueListenable: favouriteDeviceIds,
            builder: (context, favouriteIds, _) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isSelected = selected == device;
                    final isFavourite = favouriteIds.contains(device.id);
                    return ActionTile(
                      icon: Icons.devices_rounded,
                      label: device.name,
                      subtitle: '${device.address.address}:${device.port}',
                      selected: isSelected,
                      onTap: canSelect ? () => onSelected(device) : null,
                      trailing: IconButton(
                        icon: Icon(
                          isFavourite
                              ? Icons.favorite_sharp
                              : Icons.favorite_border,
                          color: AppColors.success.withAlpha(150),
                        ),

                        onPressed: () => onToggleFavourite(device.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        '$label: $value',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile({
    required this.icon,
    this.iconWidget,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ActionTile(
        icon: icon,
        iconWidget: iconWidget,
        label: label,
        onTap: onTap,
        iconBackgroundColor: AppColors.surfaceTertiary,
        iconColor: AppColors.textPrimary,
        showIconBackground: false,
        iconContainerSize: 36,
        iconSize: 22,
        vertical: true,
        showBorder: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }
}

class _AddMoreTile extends StatelessWidget {
  const _AddMoreTile({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ActionTile(
        icon: Icons.add_rounded,
        label: null,
        onTap: enabled ? onTap : null,
        selected: false,
        iconBackgroundColor: AppColors.surfaceTertiary,
        iconColor: AppColors.textPrimary,
        showIconBackground: false,
        iconContainerSize: 36,
        iconSize: 22,
        vertical: true,
        showBorder: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }
}

class _RefreshIconButton extends StatefulWidget {
  const _RefreshIconButton({
    required this.enabled,
    required this.refreshing,
    required this.onPressed,
  });

  final bool enabled;
  final bool refreshing;
  final Future<void> Function() onPressed;

  @override
  State<_RefreshIconButton> createState() => _RefreshIconButtonState();
}

class _RefreshIconButtonState extends State<_RefreshIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.refreshing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RefreshIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshing && !oldWidget.refreshing) {
      _controller.repeat();
    } else if (!widget.refreshing && oldWidget.refreshing) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.enabled || widget.refreshing;
    return IconButton(
      onPressed: disabled ? null : () => widget.onPressed(),
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(
          Icons.refresh_rounded,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _InstalledAppsSheet extends StatefulWidget {
  const _InstalledAppsSheet({required this.onPick});

  final ValueChanged<InstalledAppInfo> onPick;

  @override
  State<_InstalledAppsSheet> createState() => _InstalledAppsSheetState();
}

class _InstalledAppsSheetState extends State<_InstalledAppsSheet> {
  final _search = TextEditingController();
  Future<List<InstalledAppInfo>>? _appsFuture;

  @override
  void initState() {
    super.initState();
    _appsFuture = _loadApps();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<InstalledAppInfo>> _loadApps() async {
    final apps = await InstalledApps.list();
    apps.sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );
    return apps;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select app',
          style: AppTextStyles.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search apps...',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: FutureBuilder<List<InstalledAppInfo>>(
            future: _appsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data ?? const <InstalledAppInfo>[];
              final q = _search.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? all
                  : all
                        .where(
                          (a) =>
                              a.appName.toLowerCase().contains(q) ||
                              a.packageName.toLowerCase().contains(q),
                        )
                        .toList(growable: false);

              if (filtered.isEmpty) {
                return EmptyState(
                  title: 'No apps found',
                  message: 'Try another search.',
                  iconBuilder: (size) => SvgIcon(
                    asset: 'assets/svg/app.svg',
                    color: AppColors.primaryAccent,
                    size: size,
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (context, index) {
                  final app = filtered[index];
                  final iconBytes = app.iconPng;

                  return ListTile(
                    leading: iconBytes == null
                        ? SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: SvgIcon(
                                asset: 'assets/svg/app.svg',
                                color: AppColors.primaryAccent,
                                size: 22,
                              ),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              iconBytes,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                    title: Text(
                      app.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => widget.onPick(app),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
