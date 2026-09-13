import 'dart:io';

class WindowsNetworkProfile {
  const WindowsNetworkProfile();

  Future<bool> isActiveNetworkPrivate() async {
    if (!Platform.isWindows) return false;

    const command = r'''
@(Get-NetConnectionProfile |
  Where-Object {
    $_.NetworkCategory -eq 'Private' -and
    ($_.IPv4Connectivity -ne 'Disconnected' -or
     $_.IPv6Connectivity -ne 'Disconnected')
  }).Count -gt 0
''';

    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        command,
      ], runInShell: false);

      if (result.exitCode != 0) return false;
      return result.stdout.toString().trim().toLowerCase() == 'true';
    } catch (_) {
      // A failed check should not block the application from starting.
      return false;
    }
  }

  Future<void> openNetworkSettings() async {
    if (!Platform.isWindows) return;

    try {
      await Process.start('explorer.exe', ['ms-settings:network-wifi']);
    } catch (_) {
      // Windows Settings may be unavailable in restricted environments.
    }
  }
}
