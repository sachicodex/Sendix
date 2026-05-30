import 'dart:async';
import 'dart:io';

import 'package:sendix/core/networking/constants.dart';
import 'package:sendix/models/device.dart';

class SocketManager {
  SocketManager({int? port}) : _port = port ?? kTransferPort;

  final int _port;
  ServerSocket? _server;
  final StreamController<Socket> _incomingController =
      StreamController<Socket>.broadcast();

  Stream<Socket> get incomingConnections => _incomingController.stream;

  Future<void> startServer() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
    _server!.listen(_incomingController.add);
  }

  Future<void> stopServer() async {
    await _server?.close();
    await _incomingController.close();
  }

  Future<Socket> connect(DeviceInfo device) {
    return Socket.connect(device.address, device.port);
  }
}
