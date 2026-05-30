import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/networking/constants.dart';
import 'package:sendix/core/networking/device_identity.dart';
import 'package:sendix/core/networking/discovery_service.dart';
import 'package:sendix/core/networking/socket_manager.dart';
import 'package:sendix/core/networking/transfer_control.dart';
import 'package:sendix/core/networking/transfer_engine.dart';
import 'package:sendix/models/device.dart';
import 'package:sendix/models/transfer.dart';

class SendController {
  SendController({
    required this.identity,
    required DiscoveryService discoveryService,
    required SocketManager socketManager,
    required TransferEngine transferEngine,
    required FileManager fileManager,
  }) : _discovery = discoveryService,
       _socketManager = socketManager,
       _transferEngine = transferEngine,
       _fileManager = fileManager;

  final DeviceIdentity identity;
  final DiscoveryService _discovery;
  final SocketManager _socketManager;
  final TransferEngine _transferEngine;
  final FileManager _fileManager;

  final ValueNotifier<List<TransferProgress>> transfers =
      ValueNotifier<List<TransferProgress>>([]);

  Stream<List<DeviceInfo>> get devices => _discovery.devices;

  final Map<String, TransferControl> _controls = {};

  TransferControl? controlFor(String transferId) => _controls[transferId];

  void pauseTransfer(String transferId) =>
      _controls[transferId]?.pauseTransfer();

  void resumeTransfer(String transferId) =>
      _controls[transferId]?.resumeTransfer();

  void cancelTransfer(String transferId) =>
      _controls[transferId]?.cancelTransfer();

  Future<void> start() async {
    await _discovery.start();
  }

  Future<void> ensureDiscovery({bool broadcast = false}) async {
    await _discovery.ensureStarted(broadcast: broadcast);
  }

  Future<void> refreshDevices({
    Duration duration = const Duration(seconds: 3),
  }) => _discovery.refresh(duration: duration);

  Future<void> dispose() async {
    for (final c in _controls.values) {
      await c.dispose();
    }
    _controls.clear();
    transfers.dispose();
    await _discovery.stop();
  }

  Future<List<TransferFile>> pickFiles() => _fileManager.pickFiles();

  Future<List<TransferFile>> pickDirectory() => _fileManager.pickDirectory();

  Future<void> sendFiles(DeviceInfo device, List<TransferFile> files) async {
    if (files.isEmpty) return;
    final socket = await _socketManager.connect(device);
    final localAddress = _discovery.localAddress ?? InternetAddress.anyIPv4;
    final localDevice = DeviceInfo(
      id: identity.id,
      name: identity.name,
      address: localAddress,
      port: kTransferPort,
      capabilities: identity.capabilities,
    );

    await _transferEngine.sendFiles(
      socket: socket,
      localDevice: localDevice,
      files: files,
      onProgress: _updateProgress,
      control: TransferControl(),
      onControlReady: (id, control) {
        _controls[id] = control;
      },
    );
  }

  void _updateProgress(TransferProgress progress) {
    final current = List<TransferProgress>.from(transfers.value);
    final index = current.indexWhere(
      (item) => item.transferId == progress.transferId,
    );
    if (index >= 0) {
      current[index] = progress;
    } else {
      current.add(progress);
    }
    transfers.value = current;

    if (progress.status == TransferStatus.completed ||
        progress.status == TransferStatus.failed ||
        progress.status == TransferStatus.cancelled) {
      final control = _controls.remove(progress.transferId);
      unawaited(control?.dispose());
    }
  }
}
