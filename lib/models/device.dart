import 'dart:io';

class DeviceInfo {
  DeviceInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.capabilities,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String id;
  final String name;
  final InternetAddress address;
  final int port;
  final List<String> capabilities;
  final DateTime lastSeen;

  DeviceInfo copyWith({
    String? id,
    String? name,
    InternetAddress? address,
    int? port,
    List<String>? capabilities,
    DateTime? lastSeen,
  }) {
    return DeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      capabilities: capabilities ?? this.capabilities,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': address.address,
      'port': port,
      'capabilities': capabilities,
    };
  }

  static DeviceInfo fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      address: InternetAddress(json['ip'] as String),
      port: (json['port'] as num).toInt(),
      capabilities: (json['capabilities'] as List<dynamic>)
          .cast<String>()
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
