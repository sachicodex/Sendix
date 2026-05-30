import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/networking/socket_manager.dart';
import 'package:sendix/core/networking/transfer_control.dart';
import 'package:sendix/core/networking/transfer_engine.dart';
import 'package:sendix/features/receive/receive_settings_controller.dart';
import 'package:sendix/models/transfer.dart';

class ReceiveController {
  ReceiveController({
    required SocketManager socketManager,
    required TransferEngine transferEngine,
    required FileManager fileManager,
    required ReceiveSettingsController settingsController,
  }) : _socketManager = socketManager,
       _transferEngine = transferEngine,
       _fileManager = fileManager,
       _settingsController = settingsController;

  final SocketManager _socketManager;
  final TransferEngine _transferEngine;
  final FileManager _fileManager;
  final ReceiveSettingsController _settingsController;

  final StreamController<TransferRequest> _requestsController =
      StreamController<TransferRequest>.broadcast();

  final ValueNotifier<List<TransferProgress>> transfers =
      ValueNotifier<List<TransferProgress>>([]);

  Stream<TransferRequest> get incomingRequests => _requestsController.stream;

  final Map<String, TransferControl> _controls = {};
  final Map<String, DateTime> _startTimes = {};

  TransferControl? controlFor(String transferId) => _controls[transferId];
  DateTime? startTimeFor(String transferId) => _startTimes[transferId];

  void pauseTransfer(String transferId) =>
      _controls[transferId]?.pauseTransfer();

  void resumeTransfer(String transferId) =>
      _controls[transferId]?.resumeTransfer();

  void cancelTransfer(String transferId) =>
      _controls[transferId]?.cancelTransfer();

  void dismissTransfer(String transferId) {
    final current = List<TransferProgress>.from(transfers.value)
      ..removeWhere((t) => t.transferId == transferId);
    transfers.value = current;
    _startTimes.remove(transferId);
  }

  Future<void> start() async {
    await _socketManager.startServer();
    _socketManager.incomingConnections.listen(_handleSocket);
  }

  Future<void> dispose() async {
    for (final c in _controls.values) {
      await c.dispose();
    }
    _controls.clear();
    transfers.dispose();
    await _requestsController.close();
    await _socketManager.stopServer();
  }

  void _handleSocket(Socket socket) {
    unawaited(_handleIncoming(socket));
  }

  Future<void> _handleIncoming(Socket socket) async {
    final targetDir = await _fileManager.getReceiveDirectory(
      customPath: _settingsController.customSavePath.value,
    );
    try {
      await _transferEngine.receive(
        socket: socket,
        targetDirectory: targetDir,
        onApprove: _awaitApproval,
        onProgress: _updateProgress,
        control: TransferControl(),
        onControlReady: (id, control) {
          _controls[id] = control;
        },
      );
    } catch (error) {
      debugPrint('Receive failed: $error');
    }
  }

  Future<bool> _awaitApproval(TransferRequest incoming) {
    final completer = Completer<bool>();
    final request = TransferRequest(
      transferId: incoming.transferId,
      from: incoming.from,
      files: incoming.files,
      totalBytes: incoming.totalBytes,
      respond: (approved) {
        if (!completer.isCompleted) {
          completer.complete(approved);
        }
      },
    );
    _requestsController.add(request);
    return completer.future;
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
      _startTimes.putIfAbsent(progress.transferId, DateTime.now);
    }
    transfers.value = current;

    if (progress.status != TransferStatus.inProgress) {
      final control = _controls.remove(progress.transferId);
      unawaited(control?.dispose());
    }
  }
}
