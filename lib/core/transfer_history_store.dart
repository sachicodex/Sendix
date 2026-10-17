import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sendix/models/transfer.dart';

class TransferHistoryStore {
  TransferHistoryStore._(this._file, this._records);

  final File _file;
  final List<TransferProgress> _records;
  Future<void> _writeQueue = Future<void>.value();

  static Future<TransferHistoryStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}transfer_history.json',
    );
    final records = <TransferProgress>[];
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final record = TransferProgress.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (record != null &&
                  record.status != TransferStatus.inProgress) {
                records.add(record);
              }
            }
          }
        }
      } catch (_) {
        // A damaged history file should never prevent the app from starting.
      }
    }
    return TransferHistoryStore._(file, records);
  }

  List<TransferProgress> recordsFor(TransferDirection direction) =>
      List.unmodifiable(
        _records.where((record) => record.direction == direction),
      );

  Future<void> record(TransferProgress progress) {
    if (progress.status == TransferStatus.inProgress ||
        progress.status == TransferStatus.pending) {
      return Future<void>.value();
    }
    final index = _records.indexWhere(
      (record) => record.transferId == progress.transferId,
    );
    if (index >= 0) {
      _records[index] = progress;
    } else {
      _records.add(progress);
    }
    return _enqueueWrite();
  }

  Future<void> remove(String transferId) {
    _records.removeWhere((record) => record.transferId == transferId);
    return _enqueueWrite();
  }

  Future<void> _enqueueWrite() {
    _writeQueue = _writeQueue.then((_) async {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(_records.map((record) => record.toJson()).toList()),
      );
      await temporary.rename(_file.path);
    });
    return _writeQueue;
  }
}
