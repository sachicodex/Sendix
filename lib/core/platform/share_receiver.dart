import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShareReceiver {
  static const EventChannel _androidChannel = EventChannel(
    'sendix/share_events',
  );

  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();

  Stream<List<String>> get sharedPaths => _controller.stream;

  StreamSubscription<dynamic>? _androidSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (!kIsWeb && Platform.isAndroid) {
      _androidSub = _androidChannel.receiveBroadcastStream().listen((event) {
        if (event is! List) return;
        final paths = event.whereType<String>().toList(growable: false);
        if (paths.isEmpty) return;
        _controller.add(paths);
      }, onError: (_) {});
      return;
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final args = Platform.executableArguments;
      final paths = args
          .where((a) {
            final candidate = a.trim();
            if (candidate.isEmpty) return false;
            if (candidate.startsWith('-')) return false; // e.g. --packages=...
            return File(candidate).existsSync() ||
                Directory(candidate).existsSync();
          })
          .toList(growable: false);

      if (paths.isNotEmpty) {
        scheduleMicrotask(() => _controller.add(paths));
      }
    }
  }

  Future<void> dispose() async {
    await _androidSub?.cancel();
    await _controller.close();
  }
}
