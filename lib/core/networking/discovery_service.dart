import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:sendix/core/networking/constants.dart';
import 'package:sendix/core/networking/device_identity.dart';
import 'package:sendix/models/device.dart';

class DiscoveryService {
  DiscoveryService({required this.identity, int? discoveryPort})
    : _discoveryPort = discoveryPort ?? kDiscoveryPort;

  final DeviceIdentity identity;
  final int _discoveryPort;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  Timer? _healthTimer;
  InternetAddress? _localAddress;
  InternetAddress? _broadcastAddress;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _stopped = false;
  bool _starting = false;

  final Map<String, DeviceInfo> _devices = {};
  final StreamController<List<DeviceInfo>> _devicesController =
      StreamController<List<DeviceInfo>>.broadcast();

  Stream<List<DeviceInfo>> get devices => _devicesController.stream;
  InternetAddress? get localAddress => _localAddress;

  void _cleanup({bool keepHealthTimer = false}) {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    if (!keepHealthTimer) {
      _healthTimer?.cancel();
      _healthTimer = null;
    }
    _socket?.close();
    _socket = null;
    _localAddress = null;
    _broadcastAddress = null;
    _devices.clear();
    if (!_devicesController.isClosed) {
      _devicesController.add(_devices.values.toList());
    }
  }

  bool _hasNetworkForDiscovery(List<ConnectivityResult> results) {
    return results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
  }

  Future<void> start() async {
    if (_starting) return;
    _starting = true;
    _stopped = false;
    try {
      _cleanup();
      await _bindSocket();
      _broadcastTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _broadcastPresence(),
      );
      _pruneTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _pruneStale(),
      );
      _healthTimer = Timer.periodic(
        const Duration(seconds: 8),
        (_) => _healthCheck(),
      );
      _broadcastPresence();
      _connectivitySub ??= Connectivity().onConnectivityChanged.listen(
        _onConnectivityChanged,
      );
    } finally {
      _starting = false;
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_stopped) return;
    if (_hasNetworkForDiscovery(results)) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_stopped) return;
        start();
      });
    } else {
      _cleanup(keepHealthTimer: true);
    }
  }

  Future<void> stop() async {
    _stopped = true;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _cleanup();
    if (!_devicesController.isClosed) {
      await _devicesController.close();
    }
  }

  Future<void> ensureStarted({bool broadcast = false}) async {
    if (_stopped) return;
    final results = await Connectivity().checkConnectivity();
    if (!_hasNetworkForDiscovery(results)) {
      if (_socket != null) {
        _cleanup(keepHealthTimer: true);
      }
      return;
    }
    if (_socket == null) {
      await start();
      return;
    }
    if (broadcast) {
      broadcastNow();
    }
  }

  Future<void> refresh({Duration duration = const Duration(seconds: 3)}) async {
    _devices.clear();
    _emitDevices();

    for (var i = 0; i < 3; i++) {
      broadcastNow();
      if (i < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }

    await Future<void>.delayed(duration);
  }

  void broadcastNow() => _broadcastPresence();

  Future<void> _bindSocket() async {
    _localAddress = await _resolveLocalAddress();
    _broadcastAddress = await _resolveBroadcastAddress(_localAddress);
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _discoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    _socket!.broadcastEnabled = true;
    _socket!.listen(_handleEvent);
  }

  Future<void> _healthCheck() async {
    if (_stopped) return;
    final results = await Connectivity().checkConnectivity();
    if (!_hasNetworkForDiscovery(results)) {
      if (_socket != null) {
        _cleanup(keepHealthTimer: true);
      }
      return;
    }
    if (_socket == null) {
      await start();
      return;
    }
    final nextLocal = await _resolveLocalAddress();
    if (_localAddress?.address != nextLocal.address &&
        nextLocal.address != '0.0.0.0') {
      await start();
      return;
    }
    final nextBroadcast = await _resolveBroadcastAddress(_localAddress);
    if (_broadcastAddress?.address != nextBroadcast.address) {
      _broadcastAddress = nextBroadcast;
      broadcastNow();
    }
  }

  void _handleEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      final message = utf8.decode(datagram.data);
      final payload = jsonDecode(message) as Map<String, dynamic>;
      if (payload['magic'] != kDiscoveryMagic) return;
      if (payload['id'] == identity.id) return;

      final ipString = payload['ip'] as String;
      final address = ipString == '0.0.0.0'
          ? datagram.address
          : InternetAddress(ipString);
      final device = DeviceInfo(
        id: payload['id'] as String,
        name: payload['name'] as String,
        address: address,
        port: (payload['port'] as num).toInt(),
        capabilities: (payload['capabilities'] as List<dynamic>)
            .cast<String>()
            .toList(),
        lastSeen: DateTime.now(),
      );

      _devices[device.id] = device;
      _emitDevices();
    } catch (_) {}
  }

  void _emitDevices() {
    _devicesController.add(
      _devices.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  void _pruneStale() {
    final now = DateTime.now();
    _devices.removeWhere(
      (_, device) => now.difference(device.lastSeen).inSeconds > 10,
    );
    _emitDevices();
  }

  void _broadcastPresence() {
    final socket = _socket;
    if (socket == null) return;
    final address = _localAddress ?? InternetAddress.anyIPv4;
    final payload = {
      'magic': kDiscoveryMagic,
      'protocol': kProtocolVersion,
      'id': identity.id,
      'name': identity.name,
      'ip': address.address,
      'port': kTransferPort,
      'capabilities': identity.capabilities,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    final bytes = utf8.encode(jsonEncode(payload));
    socket.send(
      bytes,
      _broadcastAddress ?? InternetAddress('255.255.255.255'),
      _discoveryPort,
    );
  }

  Future<InternetAddress> _resolveLocalAddress() async {
    final info = NetworkInfo();
    String? wifiIp;
    try {
      wifiIp = await info.getWifiIP();
    } catch (_) {
      wifiIp = null;
    }
    if (wifiIp != null && wifiIp.isNotEmpty) {
      return InternetAddress(wifiIp);
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr;
        }
      }
    } catch (_) {}

    return InternetAddress.anyIPv4;
  }

  Future<InternetAddress> _resolveBroadcastAddress(
    InternetAddress? local,
  ) async {
    final info = NetworkInfo();

    try {
      final wifiBroadcast = await info.getWifiBroadcast();
      if (wifiBroadcast != null && wifiBroadcast.trim().isNotEmpty) {
        return InternetAddress(wifiBroadcast.trim());
      }
    } catch (_) {}

    try {
      final ip = await info.getWifiIP();
      final mask = await info.getWifiSubmask();
      final ipInt = _ipv4ToInt(ip);
      final maskInt = _ipv4ToInt(mask);
      if (ipInt != null && maskInt != null) {
        final broadcast = (ipInt & maskInt) | (~maskInt & 0xFFFFFFFF);
        return InternetAddress(_intToIpv4(broadcast));
      }
    } catch (_) {}

    if (local != null &&
        local.type == InternetAddressType.IPv4 &&
        local.address != '0.0.0.0') {
      final parts = local.address.split('.');
      if (parts.length == 4) {
        return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }

    return InternetAddress('255.255.255.255');
  }

  int? _ipv4ToInt(String? ip) {
    if (ip == null) return null;
    final parts = ip.trim().split('.');
    if (parts.length != 4) return null;
    final bytes = parts.map(int.tryParse).toList(growable: false);
    if (bytes.any((b) => b == null || b < 0 || b > 255)) return null;
    return ((bytes[0]! << 24) |
            (bytes[1]! << 16) |
            (bytes[2]! << 8) |
            bytes[3]!)
        .toUnsigned(32);
  }

  String _intToIpv4(int value) {
    final v = value.toUnsigned(32);
    return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
  }
}
