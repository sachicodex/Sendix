import 'dart:async';

import 'package:flutter/foundation.dart';

enum TransferControlCommand { pause, resume, cancel }

class TransferControl {
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> cancelled = ValueNotifier<bool>(false);

  String? transferId;

  final _commands = StreamController<TransferControlCommand>.broadcast();
  Stream<TransferControlCommand> get commands => _commands.stream;

  void pauseTransfer() {
    if (cancelled.value || paused.value) return;
    paused.value = true;
    _commands.add(TransferControlCommand.pause);
  }

  void resumeTransfer() {
    if (cancelled.value || !paused.value) return;
    paused.value = false;
    _commands.add(TransferControlCommand.resume);
  }

  void cancelTransfer() {
    if (cancelled.value) return;
    cancelled.value = true;
    paused.value = false;
    _commands.add(TransferControlCommand.cancel);
  }

  void setPausedFromRemote(bool value) {
    if (cancelled.value) return;
    paused.value = value;
  }

  void setCancelledFromRemote() {
    cancelled.value = true;
    paused.value = false;
  }

  Future<void> waitIfPaused() async {
    if (!paused.value) return;
    final completer = Completer<void>();
    late final VoidCallback listener;
    listener = () {
      if (!paused.value) {
        paused.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    };
    paused.addListener(listener);
    return completer.future;
  }

  Future<void> dispose() async {
    paused.dispose();
    cancelled.dispose();
    await _commands.close();
  }
}
