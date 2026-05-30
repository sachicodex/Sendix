import 'package:sendix/models/transfer.dart';

class TransferSpeedTracker {
  final Map<String, _SpeedSample> _samples = {};

  double? update(TransferProgress progress) {
    final now = DateTime.now();
    final id = progress.transferId;
    final currentBytes = progress.transferredBytes;

    final previous = _samples[id];
    if (previous == null) {
      _samples[id] = _SpeedSample(bytes: currentBytes, at: now, emaBps: null);
      return null;
    }

    final dtMs = now.difference(previous.at).inMilliseconds;
    if (dtMs <= 0) return previous.emaBps;

    final delta = currentBytes - previous.bytes;
    final instant = delta <= 0 ? 0.0 : (delta / (dtMs / 1000.0));
    const alpha = 0.25;
    final ema = previous.emaBps == null
        ? instant
        : (previous.emaBps! * (1 - alpha) + instant * alpha);

    _samples[id] = _SpeedSample(bytes: currentBytes, at: now, emaBps: ema);

    if (progress.status != TransferStatus.inProgress) {
      _samples.remove(id);
    }

    return ema;
  }
}

class _SpeedSample {
  const _SpeedSample({
    required this.bytes,
    required this.at,
    required this.emaBps,
  });

  final int bytes;
  final DateTime at;
  final double? emaBps;
}
