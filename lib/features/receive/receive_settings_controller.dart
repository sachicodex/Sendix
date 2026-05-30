import 'package:flutter/foundation.dart';
import 'package:sendix/core/receive_settings/receive_settings_store.dart';

class ReceiveSettingsController {
  ReceiveSettingsController({required ReceiveSettingsStore store})
    : _store = store;

  final ReceiveSettingsStore _store;

  final ValueNotifier<String?> customSavePath = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> favouriteDeviceIds =
      ValueNotifier<List<String>>([]);
  final ValueNotifier<bool> skipAcceptForFavourite = ValueNotifier<bool>(false);

  Future<void> start() async {
    customSavePath.value = await _store.loadCustomSavePath();
    favouriteDeviceIds.value = await _store.loadFavouriteDeviceIds();
    skipAcceptForFavourite.value = await _store.loadSkipAcceptForFavourite();
  }

  Future<void> dispose() async {
    customSavePath.dispose();
    favouriteDeviceIds.dispose();
    skipAcceptForFavourite.dispose();
  }

  Future<void> setCustomSavePath(String? path) async {
    final normalized = (path ?? '').trim();
    final next = normalized.isEmpty ? null : normalized;
    customSavePath.value = next;
    await _store.saveCustomSavePath(next);
  }

  Future<void> toggleFavourite(String deviceId) async {
    final list = List<String>.from(favouriteDeviceIds.value);
    if (list.contains(deviceId)) {
      list.remove(deviceId);
    } else {
      list.add(deviceId);
    }
    favouriteDeviceIds.value = list;
    await _store.saveFavouriteDeviceIds(list);
  }

  Future<void> setSkipAcceptForFavourite(bool value) async {
    skipAcceptForFavourite.value = value;
    await _store.saveSkipAcceptForFavourite(value);
  }
}
