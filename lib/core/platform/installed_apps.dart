import 'package:flutter/services.dart';

class InstalledAppInfo {
  InstalledAppInfo({
    required this.appName,
    required this.packageName,
    required this.apkPath,
    required this.iconPng,
  });

  final String appName;
  final String packageName;
  final String apkPath;
  final Uint8List? iconPng;
}

class InstalledApps {
  static const MethodChannel _channel = MethodChannel('sendix/installed_apps');

  static Future<List<InstalledAppInfo>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('list');
    final items = raw ?? const <dynamic>[];
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map((m) {
          final icon = m['icon'];
          return InstalledAppInfo(
            appName: (m['appName'] as String?) ?? '',
            packageName: (m['packageName'] as String?) ?? '',
            apkPath: (m['apkPath'] as String?) ?? '',
            iconPng: icon is Uint8List ? icon : null,
          );
        })
        .where((a) => a.appName.isNotEmpty && a.packageName.isNotEmpty)
        .toList(growable: false);
  }
}
