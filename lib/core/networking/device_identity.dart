import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DeviceIdentity {
  DeviceIdentity({
    required this.id,
    required this.name,
    this.nameConfigured = false,
    required this.capabilities,
  });

  final String id;
  String name;
  bool nameConfigured;
  final List<String> capabilities;

  static Future<DeviceIdentity> load() async {
    final supportDir = await getApplicationSupportDirectory();
    final idFile = File(p.join(supportDir.path, 'device_id.txt'));
    String id;
    if (await idFile.exists()) {
      id = (await idFile.readAsString()).trim();
    } else {
      id = _randomId();
      await idFile.create(recursive: true);
      await idFile.writeAsString(id);
    }

    final nameFile = File(p.join(supportDir.path, 'device_name.txt'));
    String deviceName;
    var nameConfigured = false;
    if (await nameFile.exists()) {
      deviceName = (await nameFile.readAsString()).trim();
      nameConfigured = deviceName.isNotEmpty;
    } else {
      deviceName = '';
    }
    if (deviceName.isEmpty) deviceName = 'Sendix Device';

    return DeviceIdentity(
      id: id,
      name: deviceName,
      nameConfigured: nameConfigured,
      capabilities: const ['files', 'text', 'images'],
    );
  }

  Future<void> setName(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    name = trimmed;
    nameConfigured = true;

    final supportDir = await getApplicationSupportDirectory();
    final nameFile = File(p.join(supportDir.path, 'device_name.txt'));
    await nameFile.create(recursive: true);
    await nameFile.writeAsString(trimmed);
  }

  static String _randomId() {
    final rand = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
