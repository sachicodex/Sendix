import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:sendix/core/networking/constants.dart';
import 'package:sendix/core/networking/transfer_control.dart';
import 'package:sendix/core/networking/transfer_protocol.dart';
import 'package:sendix/models/device.dart';
import 'package:sendix/models/transfer.dart';

typedef TransferProgressCallback = void Function(TransferProgress progress);
typedef TransferApprovalCallback =
    Future<bool> Function(TransferRequest request);

class TransferEngine {
  TransferEngine({int? chunkSize, bool? compress})
    : _chunkSize = chunkSize ?? kDefaultChunkSize,
      _compress = compress ?? true;

  final int _chunkSize;
  final bool _compress;
  static const int _flushThreshold = 64;

  final GZipEncoder _gzipEncoder = GZipEncoder();
  final GZipDecoder _gzipDecoder = GZipDecoder();

  Future<void> sendFiles({
    required Socket socket,
    required DeviceInfo localDevice,
    required List<TransferFile> files,
    required TransferProgressCallback onProgress,
    TransferControl? control,
    void Function(String transferId, TransferControl control)? onControlReady,
  }) async {
    final transferId = DateTime.now().millisecondsSinceEpoch.toString();
    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final transferControl = control ?? TransferControl();
    transferControl.transferId = transferId;
    onControlReady?.call(transferId, transferControl);

    final hello = {
      'protocol': kProtocolVersion,
      'transferId': transferId,
      'device': localDevice.toJson(),
      'files': files.map((f) => f.toJson()).toList(),
      'totalBytes': totalBytes,
      'compress': _compress,
    };
    _sendJson(socket, FrameType.hello, hello);

    final decoded = FrameDecoder().bind(socket).asBroadcastStream();
    var ackedBytes = 0;
    var currentFileName = files.isEmpty ? 'Transfer' : files.first.name;

    onProgress(
      TransferProgress(
        transferId: transferId,
        direction: TransferDirection.send,
        fileName: currentFileName,
        totalBytes: totalBytes,
        transferredBytes: 0,
        status: TransferStatus.pending,
      ),
    );

    try {
      final response = await decoded
          .firstWhere(
            (frame) =>
                frame.type == FrameType.accept ||
                frame.type == FrameType.reject ||
                frame.type == FrameType.error,
          )
          .timeout(const Duration(seconds: 30));

      if (response.type == FrameType.reject) {
        throw const SocketException('Transfer rejected by receiver.');
      }
      if (response.type == FrameType.error) {
        throw const SocketException('Receiver reported an error.');
      }
    } catch (error) {
      try {
        await socket.close();
      } catch (_) {
        socket.destroy();
      }

      onProgress(
        TransferProgress(
          transferId: transferId,
          direction: TransferDirection.send,
          fileName: currentFileName,
          totalBytes: totalBytes,
          transferredBytes: 0,
          status: TransferStatus.failed,
          error: error.toString(),
        ),
      );
      return;
    }

    var lastProgressBytes = 0;
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);

    late final StreamSubscription<TransferControlCommand> controlSub;
    controlSub = transferControl.commands.listen((cmd) {
      if (cmd == TransferControlCommand.pause) {
        _sendFrame(socket, FrameType.pause, const <int>[]);
      } else if (cmd == TransferControlCommand.resume) {
        _sendFrame(socket, FrameType.resume, const <int>[]);
      } else if (cmd == TransferControlCommand.cancel) {
        _sendFrame(socket, FrameType.cancel, const <int>[]);
        socket.destroy();
      }
    });

    late final StreamSubscription<Frame> acks;
    acks = decoded.listen((frame) {
      if (frame.type == FrameType.progress) {
        try {
          final payload = _decodeJson(frame.payload);
          final received = (payload['receivedBytes'] as num).toInt();
          if (received > ackedBytes) {
            ackedBytes = received;
            final now = DateTime.now();
            final shouldEmit =
                (ackedBytes - lastProgressBytes) >= 256 * 1024 ||
                now.difference(lastProgressAt).inMilliseconds >= 200;
            if (shouldEmit) {
              lastProgressBytes = ackedBytes;
              lastProgressAt = now;
              onProgress(
                TransferProgress(
                  transferId: transferId,
                  direction: TransferDirection.send,
                  fileName: currentFileName,
                  totalBytes: totalBytes,
                  transferredBytes: ackedBytes,
                  status: TransferStatus.inProgress,
                ),
              );
            }
          }
        } catch (_) {}
      } else if (frame.type == FrameType.error) {
        onProgress(
          TransferProgress(
            transferId: transferId,
            direction: TransferDirection.send,
            fileName: currentFileName,
            totalBytes: totalBytes,
            transferredBytes: ackedBytes,
            status: TransferStatus.failed,
            error: 'Receiver reported an error.',
          ),
        );
      } else if (frame.type == FrameType.pause) {
        transferControl.setPausedFromRemote(true);
      } else if (frame.type == FrameType.resume) {
        transferControl.setPausedFromRemote(false);
      } else if (frame.type == FrameType.cancel) {
        transferControl.setCancelledFromRemote();
        socket.destroy();
      }
    }, onError: (_) {});

    TransferStatus finalStatus = TransferStatus.completed;
    String? finalError;
    var finalTransferred = totalBytes;

    try {
      for (final file in files) {
        if (transferControl.cancelled.value) {
          throw const SocketException('Transfer cancelled.');
        }
        await transferControl.waitIfPaused();
        if (transferControl.cancelled.value) {
          throw const SocketException('Transfer cancelled.');
        }

        currentFileName = file.name;
        onProgress(
          TransferProgress(
            transferId: transferId,
            direction: TransferDirection.send,
            fileName: file.name,
            totalBytes: totalBytes,
            transferredBytes: ackedBytes,
            status: TransferStatus.inProgress,
          ),
        );

        final fileStart = {
          'name': file.name,
          'relativePath': file.relativePath,
          'size': file.size,
        };
        _sendJson(socket, FrameType.fileStart, fileStart);

        final digestSink = _SingleValueSink<crypto.Digest>();
        final shaSink = crypto.sha256.startChunkedConversion(digestSink);

        final raf = await File(file.absolutePath!).open();
        try {
          final buffer = Uint8List(_chunkSize);
          var chunksSinceFlush = 0;
          while (true) {
            if (transferControl.cancelled.value) {
              throw const SocketException('Transfer cancelled.');
            }
            await transferControl.waitIfPaused();
            if (transferControl.cancelled.value) {
              throw const SocketException('Transfer cancelled.');
            }

            final read = await raf.readInto(buffer);
            if (read == 0) break;
            final chunk = Uint8List.view(buffer.buffer, 0, read);
            shaSink.add(chunk);
            final payload = _compress ? _gzipEncoder.encode(chunk) : chunk;
            if (payload == null) {
              throw const FormatException('Failed to encode chunk.');
            }
            _sendFrame(socket, FrameType.chunk, payload);

            chunksSinceFlush++;
            if (chunksSinceFlush >= _flushThreshold) {
              chunksSinceFlush = 0;
              await socket.flush();
            }
          }
        } finally {
          await raf.close();
        }

        if (transferControl.cancelled.value) {
          throw const SocketException('Transfer cancelled.');
        }

        shaSink.close();
        final digest = digestSink.value;
        final fileEnd = {'sha256': digest.toString()};
        _sendJson(socket, FrameType.fileEnd, fileEnd);
      }

      if (transferControl.cancelled.value) {
        throw const SocketException('Transfer cancelled.');
      }
      _sendJson(socket, FrameType.transferEnd, {'transferId': transferId});
      await socket.flush();
    } catch (error) {
      if (transferControl.cancelled.value) {
        finalStatus = TransferStatus.cancelled;
        finalTransferred = ackedBytes;
      } else {
        finalStatus = TransferStatus.failed;
        finalError = error.toString();
        finalTransferred = ackedBytes;
        try {
          _sendJson(socket, FrameType.error, {'message': finalError});
          await socket.flush();
        } catch (_) {}
      }
    } finally {
      try {
        await socket.close();
      } catch (_) {
        socket.destroy();
      }
      await acks.cancel();
      await controlSub.cancel();
    }

    onProgress(
      TransferProgress(
        transferId: transferId,
        direction: TransferDirection.send,
        fileName: files.isEmpty ? 'Transfer' : currentFileName,
        totalBytes: totalBytes,
        transferredBytes: finalTransferred,
        status: finalStatus,
        error: finalError,
      ),
    );
  }

  Future<void> receive({
    required Socket socket,
    required Directory targetDirectory,
    required TransferApprovalCallback onApprove,
    required TransferProgressCallback onProgress,
    TransferControl? control,
    void Function(String transferId, TransferControl control)? onControlReady,
  }) async {
    final transferControl = control ?? TransferControl();
    final frames = StreamIterator(FrameDecoder().bind(socket));
    if (!await frames.moveNext()) {
      throw const SocketException('Connection closed before HELLO.');
    }

    final helloFrame = frames.current;
    if (helloFrame.type != FrameType.hello) {
      throw const SocketException('Expected HELLO frame.');
    }

    final hello = _decodeJson(helloFrame.payload);
    final transferId = hello['transferId'] as String;
    transferControl.transferId = transferId;
    onControlReady?.call(transferId, transferControl);
    final device = DeviceInfo.fromJson(
      (hello['device'] as Map).cast<String, dynamic>(),
    );
    final files = (hello['files'] as List<dynamic>)
        .map(
          (item) =>
              TransferFile.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
    final totalBytes = (hello['totalBytes'] as num).toInt();
    final bool compress = (hello['compress'] as bool?) ?? true;

    final approved = await onApprove(
      TransferRequest(
        transferId: transferId,
        from: device,
        files: files,
        totalBytes: totalBytes,
      ),
    );

    if (!approved) {
      _sendJson(socket, FrameType.reject, {'reason': 'declined'});
      await socket.close();
      return;
    }

    _sendJson(socket, FrameType.accept, const <String, dynamic>{});

    late final StreamSubscription<TransferControlCommand> controlSub;
    controlSub = transferControl.commands.listen((cmd) {
      if (cmd == TransferControlCommand.pause) {
        _sendFrame(socket, FrameType.pause, const <int>[]);
      } else if (cmd == TransferControlCommand.resume) {
        _sendFrame(socket, FrameType.resume, const <int>[]);
      } else if (cmd == TransferControlCommand.cancel) {
        _sendFrame(socket, FrameType.cancel, const <int>[]);
        socket.destroy();
      }
    });

    TransferFile? currentFile;
    RandomAccessFile? currentOutput;
    String? currentOutputPath;
    String? currentDisplayName;
    String? lastOutputPath;
    String lastFileName = files.isEmpty ? 'Transfer' : files.first.name;
    var receivedBytes = 0;
    var lastAckBytes = 0;
    var lastAckAt = DateTime.fromMillisecondsSinceEpoch(0);
    var currentDigestSink = _SingleValueSink<crypto.Digest>();
    var currentShaSink = crypto.sha256.startChunkedConversion(
      currentDigestSink,
    );

    final deferred = <Frame>[];

    Future<void> processFrame(Frame frame) async {
      if (transferControl.cancelled.value) {
        throw const SocketException('Transfer cancelled.');
      }

      if (frame.type == FrameType.fileStart) {
        final fileStart = _decodeJson(frame.payload);
        final startedFile = TransferFile(
          name: fileStart['name'] as String,
          relativePath: fileStart['relativePath'] as String,
          size: (fileStart['size'] as num).toInt(),
        );
        currentFile = startedFile;

        final safePath = _safeRelativePath(startedFile.relativePath);
        final outputPath = p.join(targetDirectory.path, safePath);
        final uniquePath = await _uniqueOutputPath(outputPath);
        final displayName = p.basename(uniquePath);
        currentOutputPath = uniquePath;
        currentDisplayName = displayName;
        lastOutputPath = uniquePath;
        lastFileName = displayName;
        await Directory(p.dirname(uniquePath)).create(recursive: true);
        currentOutput = await File(uniquePath).open(mode: FileMode.write);

        currentDigestSink = _SingleValueSink<crypto.Digest>();
        currentShaSink = crypto.sha256.startChunkedConversion(
          currentDigestSink,
        );

        onProgress(
          TransferProgress(
            transferId: transferId,
            direction: TransferDirection.receive,
            fileName: displayName,
            localPath: currentOutputPath,
            totalBytes: totalBytes,
            transferredBytes: receivedBytes,
            status: TransferStatus.inProgress,
          ),
        );
        return;
      }

      if (frame.type == FrameType.chunk) {
        final activeFile = currentFile;
        final activeOutput = currentOutput;
        if (activeFile == null || activeOutput == null) {
          throw const SocketException('Received chunk without file start.');
        }

        final payload = frame.payload;
        final data = compress
            ? Uint8List.fromList(_gzipDecoder.decodeBytes(payload))
            : payload;
        currentShaSink.add(data);
        await activeOutput.writeFrom(data);

        receivedBytes += data.length;

        final now = DateTime.now();
        final shouldAck =
            (receivedBytes - lastAckBytes) >= 256 * 1024 ||
            now.difference(lastAckAt).inMilliseconds >= 250;
        if (shouldAck) {
          lastAckBytes = receivedBytes;
          lastAckAt = now;
          _sendJson(socket, FrameType.progress, {
            'receivedBytes': receivedBytes,
          });
        }

        onProgress(
          TransferProgress(
            transferId: transferId,
            direction: TransferDirection.receive,
            fileName: currentDisplayName ?? activeFile.name,
            localPath: currentOutputPath,
            totalBytes: totalBytes,
            transferredBytes: receivedBytes,
            status: TransferStatus.inProgress,
          ),
        );
        return;
      }

      if (frame.type == FrameType.fileEnd) {
        final endedFile = currentFile;
        final endedOutput = currentOutput;
        if (endedFile == null || endedOutput == null) return;
        currentShaSink.close();
        final digest = currentDigestSink.value.toString();
        final remoteDigest = _decodeJson(frame.payload)['sha256'] as String;
        await endedOutput.close();
        currentOutput = null;

        if (digest != remoteDigest) {
          throw const SocketException('Checksum mismatch.');
        }

        _sendJson(socket, FrameType.progress, {'receivedBytes': receivedBytes});

        onProgress(
          TransferProgress(
            transferId: transferId,
            direction: TransferDirection.receive,
            fileName: currentDisplayName ?? endedFile.name,
            localPath: currentOutputPath,
            totalBytes: totalBytes,
            transferredBytes: receivedBytes,
            status: TransferStatus.inProgress,
          ),
        );
        currentOutputPath = null;
        currentDisplayName = null;
        currentFile = null;
        return;
      }

      if (frame.type == FrameType.transferEnd) {
        _sendJson(socket, FrameType.progress, {'receivedBytes': receivedBytes});
        throw const _TransferDone();
      }

      if (frame.type == FrameType.error) {
        throw const SocketException('Sender reported an error.');
      }
    }

    TransferStatus finalStatus = TransferStatus.completed;
    String? finalError;
    var finalTransferred = receivedBytes;

    try {
      while (await frames.moveNext()) {
        if (transferControl.cancelled.value) {
          throw const SocketException('Transfer cancelled.');
        }

        final frame = frames.current;
        if (frame.type == FrameType.pause) {
          transferControl.setPausedFromRemote(true);
          continue;
        }
        if (frame.type == FrameType.resume) {
          transferControl.setPausedFromRemote(false);
          while (deferred.isNotEmpty &&
              !transferControl.paused.value &&
              !transferControl.cancelled.value) {
            final next = deferred.removeAt(0);
            await processFrame(next);
          }
          continue;
        }
        if (frame.type == FrameType.cancel) {
          transferControl.setCancelledFromRemote();
          throw const SocketException('Transfer cancelled.');
        }

        if (transferControl.paused.value) {
          deferred.add(frame);
          continue;
        }

        await processFrame(frame);
      }

      throw const SocketException('Connection closed unexpectedly.');
    } on _TransferDone {
      finalStatus = TransferStatus.completed;
      finalTransferred = receivedBytes;
    } catch (error) {
      if (transferControl.cancelled.value) {
        finalStatus = TransferStatus.cancelled;
        finalTransferred = receivedBytes;
      } else {
        finalStatus = TransferStatus.failed;
        finalError = error.toString();
        finalTransferred = receivedBytes;
      }
    } finally {
      final openOutput = currentOutput;
      currentOutput = null;
      if (openOutput != null) {
        await openOutput.close();
      }
      try {
        await socket.close();
      } catch (_) {
        socket.destroy();
      }
      await controlSub.cancel();
    }

    onProgress(
      TransferProgress(
        transferId: transferId,
        direction: TransferDirection.receive,
        fileName: lastFileName,
        localPath: lastOutputPath,
        totalBytes: totalBytes,
        transferredBytes: finalTransferred,
        status: finalStatus,
        error: finalError,
      ),
    );
  }

  void _sendJson(Socket socket, int type, Map<String, dynamic> payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    _sendFrame(socket, type, bytes);
  }

  void _sendFrame(Socket socket, int type, List<int> payload) {
    final frame = Frame(type, Uint8List.fromList(payload));
    socket.add(FrameCodec.encode(frame));
  }

  Map<String, dynamic> _decodeJson(Uint8List payload) {
    return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  }

  String _safeRelativePath(String path) {
    final normalized = p.normalize(path).replaceAll('\\', '/');
    if (p.isAbsolute(normalized) || normalized.startsWith('..')) {
      throw const FormatException('Invalid path in transfer.');
    }
    return normalized;
  }

  Future<String> _uniqueOutputPath(String outputPath) async {
    if (!await File(outputPath).exists()) return outputPath;

    final dir = p.dirname(outputPath);
    final ext = p.extension(outputPath);
    final base = p.basenameWithoutExtension(outputPath);
    var index = 1;
    while (true) {
      final candidate = p.join(dir, '$base$index$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      index += 1;
    }
  }
}

class _TransferDone implements Exception {
  const _TransferDone();
}

class _SingleValueSink<T> implements Sink<T> {
  T? _value;

  T get value {
    final value = _value;
    if (value == null) {
      throw StateError('Value not set.');
    }
    return value;
  }

  @override
  void add(T data) {
    if (_value != null) {
      throw StateError('add may only be called once.');
    }
    _value = data;
  }

  @override
  void close() {
    if (_value == null) {
      throw StateError('add must be called once.');
    }
  }
}
