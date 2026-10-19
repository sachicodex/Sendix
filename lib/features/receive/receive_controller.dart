import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sendix/core/file_manager.dart';
import 'package:sendix/core/transfer_history_store.dart';
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
    TransferHistoryStore? historyStore,
    List<TransferProgress> initialTransfers = const [],
  }) : _socketManager = socketManager,
       _transferEngine = transferEngine,
       _fileManager = fileManager,
       _settingsController = settingsController,
       _historyStore = historyStore,
       transfers = ValueNotifier<List<TransferProgress>>(initialTransfers);

  final SocketManager _socketManager;
  final TransferEngine _transferEngine;
  final FileManager _fileManager;
  final ReceiveSettingsController _settingsController;
  final TransferHistoryStore? _historyStore;

  final StreamController<TransferRequest> _requestsController =
      StreamController<TransferRequest>.broadcast();

  final ValueNotifier<List<TransferProgress>> transfers;

  Stream<TransferRequest> get incomingRequests => _requestsController.stream;

  final Map<String, TransferControl> _controls = {};
  final Map<String, DateTime> _startTimes = {};
  final Map<String, TransferProgress> _pendingProgress = {};
  final Map<String, Timer> _progressTimers = {};
  static const Duration _progressUpdateInterval = Duration(milliseconds: 50);

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
    unawaited(_historyStore?.remove(transferId) ?? Future<void>.value());
  }

  Future<void> start() async {
    await _socketManager.startServer();
    _socketManager.incomingConnections.listen(_handleSocket);
  }

  Future<void> dispose() async {
    for (final timer in _progressTimers.values) {
      timer.cancel();
    }
    _progressTimers.clear();
    _pendingProgress.clear();
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
    if (progress.status == TransferStatus.inProgress) {
      _pendingProgress[progress.transferId] = progress;
      if (!_progressTimers.containsKey(progress.transferId)) {
        _publishProgress(progress);
        _pendingProgress.remove(progress.transferId);
        _progressTimers[progress.transferId] = Timer.periodic(
          _progressUpdateInterval,
          (_) {
            final latest = _pendingProgress.remove(progress.transferId);
            if (latest != null) _publishProgress(latest);
          },
        );
      }
      return;
    }

    _progressTimers.remove(progress.transferId)?.cancel();
    _pendingProgress.remove(progress.transferId);
    _publishProgress(progress);
  }

  void _publishProgress(TransferProgress progress) {
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
    unawaited(_historyStore?.record(progress) ?? Future<void>.value());

    if (progress.status != TransferStatus.inProgress) {
      final control = _controls.remove(progress.transferId);
      unawaited(control?.dispose());
    }
  }
}
