import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/error_messages.dart';
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
import 'package:sendix/widgets/Glass Card/glass_carrd.dart';

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

class _SendPageState extends State<SendPage>
    with SingleTickerProviderStateMixin {
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
  final Map<String, Uint8List> _knownAppIcons = {};
  final Set<String> _loadingFileIcons = {};
  late final AnimationController _dropPulse;

  @override
  void initState() {
    super.initState();
    _dropPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    widget.sharedFiles.addListener(_onSharedFilesChanged);
    _applySharedFiles(widget.sharedFiles.value);
    unawaited(_loadKnownAppIcons());
  }

  Future<void> _loadKnownAppIcons() async {
    if (!_isAndroidPlatform) return;
    try {
      final apps = await InstalledApps.list();
      if (!mounted) return;
      setState(() {
        for (final app in apps) {
          final icon = app.iconPng;
          if (icon != null && app.apkPath.isNotEmpty) {
            _knownAppIcons[p.normalize(app.apkPath)] = icon;
          }
        }
      });
    } catch (_) {
      // The platform app icon channel is optional on desktop builds.
    }
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
    _dropPulse.dispose();
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
    final current = <TransferFile>[];
    final existing = _selectedFiles
        .map((f) => f.absolutePath ?? f.relativePath)
        .toSet();
    final added = <String>{};
    for (final f in files) {
      final key = f.absolutePath ?? f.relativePath;
      if (added.add(key) && !existing.contains(key)) {
        current.add(f);
      }
    }
    if (current.isEmpty) return;
    setState(() => _selectedFiles = [...current, ..._selectedFiles]);
    for (final file in current) {
      final path = file.absolutePath;
      if (path != null) unawaited(_loadWindowsFileIcon(path));
    }
  }

  Future<void> _loadWindowsFileIcon(String path) async {
    if (!_isWindowsPlatform || _loadingFileIcons.contains(path)) return;
    final ext = p.extension(path).toLowerCase();
    if (!{'.exe', '.msi', '.com', '.scr'}.contains(ext)) return;
    _loadingFileIcons.add(path);
    try {
      final tempDir = await getTemporaryDirectory();
      final output = p.join(tempDir.path, 'sendix_icon_${path.hashCode}.png');
      final encodedPath = base64Encode(utf8.encode(path));
      final script =
          '''
Add-Type -AssemblyName System.Drawing
\$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedPath'))
\$out = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${base64Encode(utf8.encode(output))}'))
\$icon = [System.Drawing.Icon]::ExtractAssociatedIcon(\$path)
if (\$icon -ne \$null) {
  \$bitmap = \$icon.ToBitmap()
  \$bitmap.Save(\$out, [System.Drawing.Imaging.ImageFormat]::Png)
  \$bitmap.Dispose()
  \$icon.Dispose()
}
''';
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
      final iconFile = File(output);
      if (!await iconFile.exists()) return;
      final bytes = await iconFile.readAsBytes();
      if (!mounted || bytes.isEmpty) return;
      setState(() => _knownAppIcons[p.normalize(path)] = bytes);
    } catch (_) {
      // Keep the HugeIcon fallback when Windows cannot extract an icon.
    } finally {
      _loadingFileIcons.remove(path);
    }
  }

  void _setSelectedFiles(List<TransferFile> files) {
    setState(() {
      _selectedFiles = files;
      if (files.isEmpty) {
        _selectedDevice = null;
      }
    });
    _lastAutoSendKey = null;
    for (final file in files) {
      final path = file.absolutePath;
      if (path != null) unawaited(_loadWindowsFileIcon(path));
    }
  }

  List<List<dynamic>> _hugeIconForExtension(String extension) {
    return switch (extension) {
      '.txt' ||
      '.md' ||
      '.json' ||
      '.xml' ||
      '.yaml' ||
      '.yml' ||
      '.log' ||
      '.ini' ||
      '.toml' => HugeIcons.strokeRoundedNote01,
      '.doc' ||
      '.docx' ||
      '.odt' ||
      '.rtf' => HugeIcons.strokeRoundedFileAttachment,
      '.pdf' => HugeIcons.strokeRoundedFile02,
      '.xls' ||
      '.xlsx' ||
      '.csv' ||
      '.ods' => HugeIcons.strokeRoundedFileSpreadsheet,
      '.ppt' || '.pptx' || '.odp' => HugeIcons.strokeRoundedPresentation01,
      '.mp3' ||
      '.wav' ||
      '.flac' ||
      '.aac' ||
      '.m4a' ||
      '.ogg' ||
      '.wma' => HugeIcons.strokeRoundedMusicNote01,
      '.mp4' ||
      '.mov' ||
      '.mkv' ||
      '.avi' ||
      '.webm' ||
      '.m4v' => HugeIcons.strokeRoundedFileVideo,
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.webp' ||
      '.gif' ||
      '.bmp' ||
      '.tiff' ||
      '.svg' => HugeIcons.strokeRoundedImage01,
      '.zip' ||
      '.rar' ||
      '.7z' ||
      '.tar' ||
      '.gz' ||
      '.bz2' ||
      '.xz' => HugeIcons.strokeRoundedFileZip,
      '.apk' ||
      '.aab' ||
      '.ipa' ||
      '.exe' ||
      '.msi' ||
      '.dmg' => HugeIcons.strokeRoundedPackage01,
      '.dart' ||
      '.js' ||
      '.ts' ||
      '.jsx' ||
      '.tsx' ||
      '.html' ||
      '.css' ||
      '.java' ||
      '.kt' ||
      '.swift' ||
      '.py' ||
      '.c' ||
      '.cpp' ||
      '.h' ||
      '.sql' ||
      '.sh' ||
      '.bat' => HugeIcons.strokeRoundedFileCode,
      _ => HugeIcons.strokeRoundedFile01,
    };
  }

  Future<void> _pickFiles() async {
    final files = await widget.controller.pickFiles();
    if (!mounted) return;
    _addSelectedFiles(files);
    _maybeAutoSend();
  }

  Future<void> _pickDirectory() async {
    final files = await widget.controller.pickDirectory();
    if (!mounted) return;
    _addSelectedFiles(files);
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
      backgroundColor: Colors.transparent,
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
        userErrorMessage(error),
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
        final dialogWidth = (MediaQuery.sizeOf(context).width - 40)
            .clamp(280.0, 560.0)
            .toDouble();

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: GlassCard(
            width: dialogWidth,
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(24),
            tintColor: Colors.white,
            tintOpacity: 0.065,
            borderColor: Colors.white,
            borderOpacity: 0.14,
            blurSigma: 24,
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send text',
                  style: AppTextStyles.titleLarge.copyWith(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Add a note or message to send.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  minLines: 7,
                  maxLines: 11,
                  autofocus: true,
                  style: AppTextStyles.bodyMedium.copyWith(fontSize: 15),
                  cursorColor: AppColors.primaryAccent,
                  decoration: InputDecoration(
                    hintText: 'Type text to send...',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.18),
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primaryAccent,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        foregroundColor: AppColors.bg,
                        backgroundColor: AppColors.primaryAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.of(context).pop(controller.text),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    final normalized = (text ?? '').trim();
    if (!mounted || normalized.isEmpty) return;
    await _addTextAsFile(normalized);
  }

  Future<void> _addTextAsFile(String text) async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}-'
        '${now.minute.toString().padLeft(2, '0')}';
    final path = p.join(dir.path, 'Sendix Note $date $time.txt');
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
      '.log',
      '.ini',
      '.toml',
      '.csv',
      '.dart',
      '.js',
      '.ts',
      '.jsx',
      '.tsx',
      '.html',
      '.css',
      '.java',
      '.kt',
      '.swift',
      '.py',
      '.c',
      '.cpp',
      '.h',
      '.sql',
      '.sh',
      '.bat',
    }.contains(ext);

    if (isImage) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: GlassCard(
              width: 760,
              height: 560,
              padding: const EdgeInsets.all(12),
              tintColor: AppColors.surface,
              tintOpacity: 0.96,
              borderColor: AppColors.borderFocus,
              borderOpacity: 0.9,
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
              child: _ImagePreview(path: path),
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
          final dialogWidth = (MediaQuery.sizeOf(context).width - 40)
              .clamp(280.0, 680.0)
              .toDouble();
          final maxHeight = (MediaQuery.sizeOf(context).height - 120)
              .clamp(260.0, 560.0)
              .toDouble();

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: GlassCard(
              width: dialogWidth,
              constraints: BoxConstraints(maxHeight: maxHeight),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              borderRadius: BorderRadius.circular(24),
              tintColor: Colors.white,
              tintOpacity: 0.065,
              borderColor: Colors.white,
              borderOpacity: 0.14,
              blurSigma: 24,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primaryAccent.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primaryAccent.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                        child: const Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedNote01,
                            size: 20,
                            color: AppColors.primaryAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Text note',
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close preview',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: 21,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight - 116),
                    child: FutureBuilder<String>(
                      future: File(path).readAsString(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError) {
                          return const Text('Failed to load preview.');
                        }
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              snapshot.data ?? '',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 16,
                                height: 1.5,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: SizedBox(
            width: 520,
            child: GlassCard(
              padding: const EdgeInsets.all(24),
              tintColor: AppColors.surface,
              tintOpacity: 0.96,
              borderColor: AppColors.borderFocus,
              borderOpacity: 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      HugeIcon(
                        icon: _hugeIconForExtension(ext),
                        color: AppColors.primary,
                        size: 25,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close preview',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: 21,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${ext.isEmpty ? 'File' : ext.substring(1).toUpperCase()} file · ${_formatBytes(file.size)}',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => OpenFilex.open(path),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowUpRight01,
                        size: 17,
                      ),
                      label: const Text('Open preview'),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
        userErrorMessage(error),
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
          label: 'Images',
          onTap: _pickImages,
        ),
        _QuickAddTile(
          icon: Icons.insert_drive_file_rounded,
          iconWidget: svgIcon('assets/svg/app.svg', iconFg),
          label: 'App',
          onTap: _isAndroidPlatform ? _showInstalledAppsSheet : _pickAppFiles,
        ),
        _QuickAddTile(
          icon: Icons.text_fields_rounded,
          iconWidget: svgIcon('assets/svg/text.svg', iconFg),
          label: 'Text',
          onTap: _sendText,
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
    final tiles = _quickAddTiles(
      mobileOnly: mobileQuickAdd,
    ).take(4).toList(growable: false);

    if (mobileQuickAdd) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: tiles
            .map(
              (tile) => _QuickAddTile(
                icon: tile.icon,
                iconWidget: tile.iconWidget,
                label: tile.label,
                onTap: tile.onTap,
                desktop: true,
                compact: true,
              ),
            )
            .toList(growable: false),
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

    final desktopTiles = tiles
        .map(
          (tile) => _QuickAddTile(
            icon: tile.icon,
            iconWidget: tile.iconWidget,
            label: tile.label,
            onTap: tile.onTap,
            desktop: widget.desktopLayout,
          ),
        )
        .toList(growable: false);
    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < desktopTiles.length; index++) ...[
            if (index > 0) const SizedBox(width: 12),
            Expanded(child: desktopTiles[index]),
          ],
        ],
      ),
    );
  }

  Future<void> _showAddSheet() async {
    if (_sending) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      barrierLabel: 'Close file options',
      barrierColor: Colors.black.withValues(alpha: 0.58),
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: false,
      useSafeArea: true,
      builder: (sheetContext) {
        final screenWidth = MediaQuery.sizeOf(sheetContext).width;
        final compact = screenWidth < 600;
        final sheetWidth = compact ? screenWidth : 560.0;
        final tiles = _quickAddTiles(
          mobileOnly: _useMobileQuickAdd(sheetContext),
        );
        final tileWidth = compact
            ? (sheetWidth - 72) / 2
            : (sheetWidth - 76) / 4;

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: sheetWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 8 : 16,
                0,
                compact ? 8 : 16,
                compact ? 8 : 16,
              ),
              child: GlassCard(
                width: sheetWidth,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                tintColor: Colors.white,
                tintOpacity: 0.07,
                borderColor: Colors.white,
                borderOpacity: 0.16,
                blurSigma: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        'What do you want to send?',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!compact)
                      Row(
                        children: [
                          for (
                            var index = 0;
                            index < tiles.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _QuickAddTile(
                                icon: tiles[index].icon,
                                iconWidget: tiles[index].iconWidget,
                                label: tiles[index].label,
                                desktop: true,
                                compact: true,
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  tiles[index].onTap();
                                },
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: tiles
                            .map(
                              (tile) => SizedBox(
                                width: tileWidth,
                                child: _QuickAddTile(
                                  icon: tile.icon,
                                  iconWidget: tile.iconWidget,
                                  label: tile.label,
                                  desktop: true,
                                  compact: true,
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    tile.onTap();
                                  },
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                ),
              ),
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

    Widget buildFileRow(int fileIndex) {
      final f = _selectedFiles[fileIndex];
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
      final icon = _hugeIconForExtension(ext);

      void removeThis() {
        final next = List<TransferFile>.from(_selectedFiles)
          ..removeAt(fileIndex);
        _setSelectedFiles(next);
      }

      final appIcon = path == null ? null : _knownAppIcons[p.normalize(path)];
      final preview = isImage && path != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(path),
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    HugeIcon(icon: icon, size: 25, color: AppColors.primary),
              ),
            )
          : appIcon != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                appIcon,
                width: 42,
                height: 42,
                fit: BoxFit.contain,
              ),
            )
          : HugeIcon(icon: icon, size: 25, color: AppColors.primary);

      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _sending ? null : () => _showPreview(f),
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceTertiary.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                SizedBox(width: 44, height: 44, child: Center(child: preview)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${ext.isEmpty ? 'File' : ext.substring(1).toUpperCase()} · ${_formatBytes(f.size)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove file',
                  onPressed: _sending ? null : removeThis,
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    size: 19,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final card = widget.desktopLayout
        ? GlassCard(
            padding: const EdgeInsets.all(18),
            borderRadius: BorderRadius.circular(24),
            tintColor: Colors.white,
            tintOpacity: 0.055,
            borderColor: Colors.white,
            borderOpacity: 0.13,
            blurSigma: 22,
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'What to ',
                                  style: AppTextStyles.titleLarge.copyWith(
                                    fontSize: 23,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: 'send',
                                  style: AppTextStyles.titleLarge.copyWith(
                                    fontSize: 23,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            filesCount == 0
                                ? (mobileQuickAdd
                                      ? 'Start with files or text.'
                                      : 'Start with files or text. Choose what you want to share.')
                                : 'Ready to send.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 13,
                              color: const Color(0xFFB9C5D3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D151B).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF18232B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.list_alt_rounded,
                                size: 15,
                                color: Color(0xFFB9C5D3),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Items: $filesCount',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(
                                Icons.sd_storage_outlined,
                                size: 15,
                                color: Color(0xFFB9C5D3),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Size: $sizeText',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: mobileQuickAdd ? 10 : 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  switchInCurve: Curves.easeOutCubic,
                  child: Container(
                    key: ValueKey<int>(_selectedFiles.length),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedFiles.isEmpty)
                          _quickAddGrid(compact: false),
                        if (!mobileQuickAdd) ...[
                          const SizedBox(height: 14),
                          if (_selectedFiles.isEmpty)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _sending ? null : _pickFiles,
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 154,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: const Color(0x301A2A24),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const HugeIcon(
                                            icon: HugeIcons
                                                .strokeRoundedCloudUpload,
                                            size: 44,
                                            color: Color(0xFF9BEA52),
                                          ),
                                          const SizedBox(height: 9),
                                          Text(
                                            'Drop files to add them',
                                            style: AppTextStyles.titleMedium
                                                .copyWith(
                                                  fontSize: 18,
                                                  color: AppColors.textPrimary,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'or click a category above',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  fontSize: 12,
                                                  color: const Color(
                                                    0xFFB9C5D3,
                                                  ),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: AnimatedBuilder(
                                          animation: _dropPulse,
                                          builder: (context, _) => CustomPaint(
                                            painter: _MovingDashedBorderPainter(
                                              progress: _draggingSelection
                                                  ? _dropPulse.value
                                                  : 0,
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.9),
                                              radius: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                        if (_selectedFiles.isNotEmpty) ...[
                          _AddMoreRow(
                            enabled: !_sending,
                            onTap: _showAddSheet,
                            dragging: false,
                            animation: _dropPulse,
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 330),
                            child: ListView.separated(
                              primary: false,
                              shrinkWrap: true,
                              itemCount: _selectedFiles.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) =>
                                  buildFileRow(index),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        : SectionCard(
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
                              height: widget.desktopLayout ? 220 : 140,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: widget.desktopLayout ? 0.88 : 0.45,
                                  ),
                                  style: BorderStyle.solid,
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF193526).withValues(
                                      alpha: widget.desktopLayout ? 0.42 : 0.28,
                                    ),
                                    const Color(0xFF0E1718).withValues(
                                      alpha: widget.desktopLayout ? 0.72 : 0.9,
                                    ),
                                  ],
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedCloudUpload,
                                    size: 28,
                                    color: widget.desktopLayout
                                        ? const Color(0xFF9BEA52)
                                        : AppColors.onTertiary,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Drop files to add them',
                                    style: AppTextStyles.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.desktopLayout
                                        ? 'or click a category above'
                                        : 'Drop here or click to browse',
                                    style: AppTextStyles.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ] else ...[
                      _AddMoreRow(
                        enabled: !_sending,
                        onTap: _showAddSheet,
                        dragging: false,
                        animation: _dropPulse,
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 330),
                        child: ListView.separated(
                          primary: false,
                          shrinkWrap: true,
                          itemCount: _selectedFiles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => buildFileRow(index),
                        ),
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
              enable: !_sending && !mobileQuickAdd,
              onDragEntered: (_) {
                setState(() => _draggingSelection = true);
                _dropPulse.repeat(reverse: true);
              },
              onDragExited: (_) {
                setState(() => _draggingSelection = false);
                _dropPulse.stop();
                _dropPulse.value = 0;
              },
              onDragDone: (details) {
                setState(() => _draggingSelection = false);
                _dropPulse.stop();
                _dropPulse.value = 0;
                final paths = details.files
                    .map((f) => f.path)
                    .where((p) => p.trim().isNotEmpty);
                unawaited(_handleDroppedPaths(paths));
              },
              child: card,
            ),
            if (_draggingSelection &&
                _selectedFiles.isEmpty &&
                !widget.desktopLayout)
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                height: widget.desktopLayout ? 220 : 140,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _dropPulse,
                    builder: (context, _) => CustomPaint(
                      painter: _MovingDashedBorderPainter(
                        progress: _dropPulse.value,
                        color: AppColors.primary,
                        radius: 16,
                      ),
                    ),
                  ),
                ),
              ),
            if (_draggingSelection && _selectedFiles.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _dropPulse,
                    builder: (context, _) => CustomPaint(
                      painter: _MovingDashedBorderPainter(
                        progress: _dropPulse.value,
                        color: AppColors.primary,
                        radius: AppCardTheme.base.radius.topLeft.x,
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
        hasItems: _selectedFiles.isNotEmpty,
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
                  12,
                  widget.desktopLayout ? 0 : 16,
                  12,
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
    required this.hasItems,
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
  final bool hasItems;
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
    if (!hasItems) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        borderRadius: BorderRadius.circular(18),
        blurSigma: 22,
        tintColor: Colors.white,
        tintOpacity: 0.045,
        borderColor: Colors.white,
        borderOpacity: 0.12,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: const Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedWifiDisconnected03,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Where to send',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Add items first.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.24),
                      ),
                    ),
                    child: const Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedWifiDisconnected03,
                        size: 25,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No devices nearby',
                          style: AppTextStyles.titleSmall,
                        ),
                        SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Turn on Wi-Fi and keep Sendix open on both devices.',
                            maxLines: 1,
                            style: AppTextStyles.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
                        tooltip: isFavourite
                            ? 'Remove from favourites'
                            : 'Add to favourites',
                        icon: Icon(
                          isFavourite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 25,
                          color: isFavourite
                              ? const Color(0xFFFFB547)
                              : AppColors.textTertiary,
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

class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.6, 4.0).toDouble();
    final size = context.size;
    if (size == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final ratio = next / current;
    _transform.value = Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(ratio, ratio, ratio, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_transform.value);
  }

  void _resetZoom() {
    _transform.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(top: 48, right: 8, bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 0.6,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(80),
                child: Image.file(File(widget.path), fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: 'Close preview',
            onPressed: () => Navigator.of(context).pop(),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              size: 21,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Reset zoom',
                onPressed: _resetZoom,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: () => _zoom(0.8),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedZoomOutArea,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: () => _zoom(1.25),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedZoomInArea,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MovingDashedBorderPainter extends CustomPainter {
  const _MovingDashedBorderPainter({
    required this.progress,
    required this.color,
    required this.radius,
  });

  final double progress;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 4 || size.height <= 4) return;
    const strokeWidth = 2.0;
    const dashLength = 9.0;
    const gapLength = 7.0;
    final inset = strokeWidth / 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular((radius - inset).clamp(0.0, radius)),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final metric = path.computeMetrics().first;
    final period = dashLength + gapLength;
    final offset = (progress * period) % period;
    for (var start = -offset; start < metric.length; start += period) {
      final from = start.clamp(0.0, metric.length);
      final to = (start + dashLength).clamp(0.0, metric.length);
      if (to > from) canvas.drawPath(metric.extractPath(from, to), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MovingDashedBorderPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.radius != radius;
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
    this.desktop = false,
    this.compact = false,
  });

  final IconData icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;
  final bool desktop;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hugeIcon = switch (label) {
      'File' => HugeIcons.strokeRoundedFile02,
      'Folder' => HugeIcons.strokeRoundedFolder01,
      'Images' || 'Image' => HugeIcons.strokeRoundedImage01,
      'Text' => HugeIcons.strokeRoundedNote01,
      _ => null,
    };
    if (desktop) {
      final accent = switch (label) {
        'File' => const Color(0xFF91E83A),
        'Folder' => const Color(0xFF55C7DC),
        'App' => const Color(0xFF55C7DC),
        'Images' || 'Image' => const Color(0xFFB679D6),
        'Text' => const Color(0xFFE4AB56),
        _ => AppColors.primary,
      };
      final subtitle = switch (label) {
        'File' => 'Any file type',
        'Folder' => 'Share multiple files',
        'Images' || 'Image' => 'Photos & pictures',
        'Text' => 'Notes & messages',
        _ => 'Choose an app',
      };
      final displayIcon = hugeIcon == null
          ? iconWidget
          : HugeIcon(icon: hugeIcon, size: 26, color: Colors.white);
      return SizedBox(
        height: compact ? 118 : 166,
        child: GlassCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(20),
          blurSigma: 24,
          tintColor: Colors.white,
          tintOpacity: 0.045,
          borderColor: Colors.white,
          borderOpacity: 0.14,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(0, 7),
            ),
          ],
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: compact ? 42 : 50,
                height: compact ? 42 : 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.95),
                      accent.withValues(alpha: 0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(compact ? 13 : 15),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Center(
                  child: SizedBox(
                    width: compact ? 24 : 28,
                    height: compact ? 24 : 28,
                    child: displayIcon,
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 10),
              Text(
                label,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: compact ? 14 : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                subtitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color(0xFFBBC7D5),
                  fontSize: compact ? 10 : 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 96,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        borderRadius: BorderRadius.circular(16),
        blurSigma: 22,
        tintColor: Colors.white,
        tintOpacity: 0.045,
        borderColor: Colors.white,
        borderOpacity: 0.13,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: hugeIcon == null
                    ? iconWidget
                    : HugeIcon(
                        icon: hugeIcon,
                        size: 22,
                        color: AppColors.textPrimary,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMoreRow extends StatelessWidget {
  const _AddMoreRow({
    required this.enabled,
    required this.onTap,
    required this.dragging,
    required this.animation,
  });

  final bool enabled;
  final VoidCallback onTap;
  final bool dragging;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          Positioned.fill(
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              borderRadius: BorderRadius.circular(14),
              blurSigma: 20,
              tintColor: Colors.white,
              tintOpacity: 0.04,
              borderColor: Colors.white,
              borderOpacity: 0.12,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
              onTap: enabled ? onTap : null,
              child: const Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedAdd01,
                    size: 21,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 10),
                  Text('Add more files'),
                ],
              ),
            ),
          ),
          if (dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) => CustomPaint(
                    painter: _MovingDashedBorderPainter(
                      progress: animation.value,
                      color: AppColors.primary,
                      radius: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    return GlassCard(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      borderRadius: BorderRadius.circular(26),
      tintColor: Colors.white,
      tintOpacity: 0.065,
      borderColor: Colors.white,
      borderOpacity: 0.15,
      blurSigma: 24,
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 14)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF55C7DC).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF55C7DC).withValues(alpha: 0.26),
                  ),
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedGridView,
                    size: 20,
                    color: Color(0xFF55C7DC),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select app',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose an installed app to send.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            style: AppTextStyles.bodyMedium,
            cursorColor: AppColors.primaryAccent,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search apps...',
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.primaryAccent,
                  width: 1.5,
                ),
              ),
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      tileColor: Colors.white.withValues(alpha: 0.025),
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
      ),
    );
  }
}
