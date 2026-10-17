import 'dart:io';

import 'package:flutter/foundation.dart';

/// Keeps technical diagnostics in debug builds while giving users short,
/// actionable messages in release builds.
String userErrorMessage(Object error) {
  final raw = error.toString();
  if (kDebugMode) return raw;

  final text = raw.toLowerCase();
  if (error is SocketException ||
      text.contains('socket') ||
      text.contains('connection timed out') ||
      text.contains('connection reset') ||
      text.contains('connection refused')) {
    return 'Connection lost. Check that both devices are on the same network.';
  }
  if (text.contains('permission') || text.contains('access denied')) {
    return 'Permission denied. Check the app permissions and try again.';
  }
  if (text.contains('storage') || text.contains('no space')) {
    return 'Not enough storage space to complete this action.';
  }
  if (text.contains('cancel')) return 'Transfer cancelled.';
  if (text.contains('checksum') || text.contains('verification')) {
    return 'Transfer verification failed. Please try again.';
  }
  if (text.contains('rejected') || text.contains('declined')) {
    return 'The transfer was declined.';
  }
  return 'Something went wrong. Please try again.';
}
