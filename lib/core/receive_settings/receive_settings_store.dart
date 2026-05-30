import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ReceiveSettingsStore {
  Future<File> _dataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'sendix'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File(p.join(folder.path, 'receive_settings.json'));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _dataFile();
    if (!await file.exists()) {
      return <String, dynamic>{
        'customSavePath': null,
        'favouriteDeviceIds': <String>[],
        'skipAcceptForFavourite': false,
      };
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return <String, dynamic>{
        'customSavePath': null,
        'favouriteDeviceIds': <String>[],
        'skipAcceptForFavourite': false,
      };
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, dynamic>{
        'customSavePath': null,
        'favouriteDeviceIds': <String>[],
        'skipAcceptForFavourite': false,
      };
    }
    final map = Map<String, dynamic>.from(decoded);
    map.putIfAbsent('customSavePath', () => null);
    map.putIfAbsent('favouriteDeviceIds', () => <String>[]);
    map.putIfAbsent('skipAcceptForFavourite', () => false);
    return map;
  }

  Future<void> _writeAll(Map<String, dynamic> map) async {
    final file = await _dataFile();
    await file.writeAsString(jsonEncode(map), flush: true);
  }

  Future<String?> loadCustomSavePath() async {
    final map = await _readAll();
    final path = map['customSavePath'] as String?;
    if (path == null || path.trim().isEmpty) return null;
    return path;
  }

  Future<void> saveCustomSavePath(String? path) async {
    final map = await _readAll();
    map['customSavePath'] = path;
    await _writeAll(map);
  }

  Future<List<String>> loadFavouriteDeviceIds() async {
    final map = await _readAll();
    final list = map['favouriteDeviceIds'];
    if (list is! List) return [];
    return list.map((e) => e.toString()).toList();
  }

  Future<void> saveFavouriteDeviceIds(List<String> ids) async {
    final map = await _readAll();
    map['favouriteDeviceIds'] = ids;
    await _writeAll(map);
  }

  Future<bool> loadSkipAcceptForFavourite() async {
    final map = await _readAll();
    return map['skipAcceptForFavourite'] as bool? ?? false;
  }

  Future<void> saveSkipAcceptForFavourite(bool value) async {
    final map = await _readAll();
    map['skipAcceptForFavourite'] = value;
    await _writeAll(map);
  }
}
