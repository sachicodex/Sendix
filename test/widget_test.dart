import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/receive_settings/receive_settings_store.dart';
import 'package:sendix/core/networking/device_identity.dart';
import 'package:sendix/core/networking/discovery_service.dart';
import 'package:sendix/core/networking/socket_manager.dart';
import 'package:sendix/core/networking/transfer_engine.dart';
import 'package:sendix/features/receive/receive_controller.dart';
import 'package:sendix/features/receive/receive_settings_controller.dart';
import 'package:sendix/features/send/send_controller.dart';
import 'package:sendix/main.dart';
import 'package:sendix/models/device.dart';
import 'package:sendix/models/transfer.dart';

void main() {
  testWidgets('Sendix app builds', (WidgetTester tester) async {
    final fileManager = _TestFileManager();
    final receiveSettingsController = ReceiveSettingsController(
      store: _FakeReceiveSettingsStore(),
    );
    final sendController = _FakeSendController(fileManager: fileManager);
    final receiveController = _FakeReceiveController(
      fileManager: fileManager,
      settingsController: receiveSettingsController,
    );

    await tester.pumpWidget(
      SendixApp(
        sendController: sendController,
        receiveController: receiveController,
        receiveSettingsController: receiveSettingsController,
        fileManager: fileManager,
      ),
    );
    await tester.pump();

    expect(find.text('SENDIX'), findsWidgets);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
  });
}

class _TestFileManager extends FileManager {
  @override
  Future<List<TransferFile>> pickFiles() async => [];

  @override
  Future<List<TransferFile>> pickDirectory() async => [];

  @override
  Future<Directory> getReceiveDirectory({String? customPath}) async {
    return Directory.systemTemp.createTemp('sendix_test_');
  }
}

class _FakeReceiveSettingsStore extends ReceiveSettingsStore {
  String? _customSavePath;

  @override
  Future<String?> loadCustomSavePath() async => _customSavePath;

  @override
  Future<void> saveCustomSavePath(String? path) async {
    _customSavePath = path;
  }
}

class _FakeSendController extends SendController {
  _FakeSendController({required super.fileManager})
    : super(
        identity: DeviceIdentity(
          id: 'test-device',
          name: 'Test Device',
          capabilities: const <String>[],
        ),
        discoveryService: DiscoveryService(
          identity: DeviceIdentity(
            id: 'test-device',
            name: 'Test Device',
            capabilities: const <String>[],
          ),
        ),
        socketManager: SocketManager(port: 0),
        transferEngine: TransferEngine(),
      );

  @override
  Stream<List<DeviceInfo>> get devices => Stream.value(const <DeviceInfo>[]);

  @override
  Future<void> start() async {}

  @override
  Future<List<TransferFile>> pickFiles() async => [];

  @override
  Future<List<TransferFile>> pickDirectory() async => [];

  @override
  Future<void> sendFiles(DeviceInfo device, List<TransferFile> files) async {}
}

class _FakeReceiveController extends ReceiveController {
  _FakeReceiveController({
    required super.fileManager,
    required super.settingsController,
  }) : super(
         socketManager: SocketManager(port: 0),
         transferEngine: TransferEngine(),
       );

  @override
  Future<void> start() async {}
}
