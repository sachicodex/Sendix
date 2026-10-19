import 'dart:io';

/// Converts technical transfer errors into short, actionable messages.
String userErrorMessage(Object error) {
  final raw = error.toString();
  final text = raw.toLowerCase();
  if (text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('future not completed')) {
    return 'The transfer timed out. Please try again.';
  }
  if (error is SocketException ||
      text.contains('socket') ||
      text.contains('connection timed out') ||
      text.contains('connection reset') ||
      text.contains('connection refused')) {
    return 'Connection lost. Check both devices and try again.';
  }
  if (text.contains('permission') || text.contains('access denied')) {
    return 'Sendix cannot access this file or folder.';
  }
  if (text.contains('storage') || text.contains('no space')) {
    return 'Not enough storage space to receive this file.';
  }
  if (text.contains('cancel')) return 'Transfer cancelled.';
  if (text.contains('checksum') || text.contains('verification')) {
    return 'Transfer verification failed. Please try again.';
  }
  if (text.contains('rejected') || text.contains('declined')) {
    return 'The transfer was declined.';
  }
  return 'The transfer could not be completed. Please try again.';
}
