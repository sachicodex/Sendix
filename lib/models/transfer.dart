import 'package:sendix/models/device.dart';

enum TransferDirection { send, receive }

enum TransferStatus { pending, inProgress, completed, failed, cancelled }

class TransferFile {
  TransferFile({
    required this.name,
    required this.relativePath,
    required this.size,
    this.absolutePath,
  });

  final String name;
  final String relativePath;
  final int size;
  final String? absolutePath;

  Map<String, dynamic> toJson() {
    return {'name': name, 'relativePath': relativePath, 'size': size};
  }

  static TransferFile fromJson(Map<String, dynamic> json) {
    return TransferFile(
      name: json['name'] as String,
      relativePath: json['relativePath'] as String,
      size: (json['size'] as num).toInt(),
    );
  }
}

class TransferProgress {
  TransferProgress({
    required this.transferId,
    required this.direction,
    required this.fileName,
    this.localPath,
    required this.totalBytes,
    required this.transferredBytes,
    required this.status,
    this.error,
  });

  final String transferId;
  final TransferDirection direction;
  final String fileName;
  final String? localPath;
  final int totalBytes;
  final int transferredBytes;
  final TransferStatus status;
  final String? error;

  double get progress {
    if (totalBytes == 0) return 0;
    return (transferredBytes / totalBytes).clamp(0.0, 1.0);
  }

  TransferProgress copyWith({
    String? transferId,
    TransferDirection? direction,
    String? fileName,
    String? localPath,
    int? totalBytes,
    int? transferredBytes,
    TransferStatus? status,
    String? error,
  }) {
    return TransferProgress(
      transferId: transferId ?? this.transferId,
      direction: direction ?? this.direction,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}

class TransferRequest {
  TransferRequest({
    required this.transferId,
    required this.from,
    required this.files,
    required this.totalBytes,
    void Function(bool approved)? respond,
  }) : respond = respond ?? _noop;

  final String transferId;
  final DeviceInfo from;
  final List<TransferFile> files;
  final int totalBytes;
  final void Function(bool approved) respond;

  static void _noop(bool _) {}
}
