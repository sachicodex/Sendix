import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/networking/device_identity.dart';
import 'package:sendix/core/networking/discovery_service.dart';
import 'package:sendix/core/networking/socket_manager.dart';
import 'package:sendix/core/receive_settings/receive_settings_store.dart';
import 'package:sendix/core/networking/transfer_engine.dart';
import 'package:sendix/features/receive/receive_controller.dart';
import 'package:sendix/features/receive/receive_settings_controller.dart';
import 'package:sendix/features/send/send_controller.dart';
import 'package:sendix/ui/app_scroll_behavior.dart';
import 'package:sendix/ui/home_page.dart';
import 'package:sendix/ui/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindowsWindow();

  final identity = await DeviceIdentity.load();
  final discoveryService = DiscoveryService(identity: identity);
  final socketManager = SocketManager();
  final transferEngine = TransferEngine();
  final fileManager = FileManager();
  final receiveSettingsController = ReceiveSettingsController(
    store: ReceiveSettingsStore(),
  );

  final sendController = SendController(
    identity: identity,
    discoveryService: discoveryService,
    socketManager: socketManager,
    transferEngine: transferEngine,
    fileManager: fileManager,
  );

  final receiveController = ReceiveController(
    socketManager: socketManager,
    transferEngine: transferEngine,
    fileManager: fileManager,
    settingsController: receiveSettingsController,
  );

  runApp(
    SendixApp(
      sendController: sendController,
      receiveController: receiveController,
      receiveSettingsController: receiveSettingsController,
      fileManager: fileManager,
    ),
  );
}

Future<void> _configureWindowsWindow() async {
  if (!Platform.isWindows) return;
  await windowManager.ensureInitialized();

  const aspectW = 5.0;
  const aspectH = 3.0;

  final screen = await getCurrentScreen();
  final visible = screen?.visibleFrame;

  double width = 1000;
  double height = width * aspectH / aspectW;

  if (visible != null) {
    final maxWidth = (visible.width * 0.80).clamp(820.0, 1400.0);
    width = maxWidth;
    height = width * aspectH / aspectW;

    final maxHeight = (visible.height * 0.80).clamp(520.0, 1000.0);
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectW / aspectH;
    }

    final left = visible.left + (visible.width - width) / 2;
    final top = visible.top + (visible.height - height) / 2;
    setWindowFrame(Rect.fromLTWH(left, top, width, height));
  } else {
    setWindowFrame(Rect.fromLTWH(120, 120, width, height));
  }

  setWindowMinSize(const Size(820, 520));
  setWindowTitle('Sendix');
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
}

class SendixApp extends StatelessWidget {
  const SendixApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sendix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      scrollBehavior: const AppScrollBehavior(),
      home: HomePage(
        sendController: sendController,
        receiveController: receiveController,
        receiveSettingsController: receiveSettingsController,
        fileManager: fileManager,
      ),
    );
  }
}
