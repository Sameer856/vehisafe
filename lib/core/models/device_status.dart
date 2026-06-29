class DeviceStatus {
  final bool isConnected;
  final int batteryPercent;
  final DateTime? lastSeen;
  final String firmwareVersion;
  final String currentMode; // Boot, Configuration, Monitoring, Alert
  final String networkStatus; // LTE Connected, Local WiFi, Searching..., Offline
  final String gpsStatus; // GPS Acquiring, GPS Locked, No Signal
  final DateTime? lastSyncTime;
  final double? latitude;
  final double? longitude;
  final String deviceName;
  final int satellites;
  final double speed;

  DeviceStatus({
    required this.isConnected,
    required this.batteryPercent,
    this.lastSeen,
    required this.firmwareVersion,
    this.currentMode = 'Monitoring',
    this.networkStatus = 'LTE Connected',
    this.gpsStatus = 'GPS Locked',
    this.lastSyncTime,
    this.latitude = 37.77492,
    this.longitude = -122.41941,
    this.deviceName = 'VehiSafe',
    this.satellites = 0,
    this.speed = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'isConnected': isConnected,
      'batteryPercent': batteryPercent,
      'lastSeen': lastSeen?.toIso8601String(),
      'firmwareVersion': firmwareVersion,
      'currentMode': currentMode,
      'networkStatus': networkStatus,
      'gpsStatus': gpsStatus,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'deviceName': deviceName,
      'satellites': satellites,
      'speed': speed,
    };
  }

  factory DeviceStatus.fromMap(Map<dynamic, dynamic> map) {
    return DeviceStatus(
      isConnected: map['isConnected'] as bool,
      batteryPercent: map['batteryPercent'] as int,
      lastSeen: map['lastSeen'] != null ? DateTime.parse(map['lastSeen'] as String) : null,
      firmwareVersion: map['firmwareVersion'] as String,
      currentMode: map['currentMode'] as String? ?? 'Monitoring',
      networkStatus: map['networkStatus'] as String? ?? 'LTE Connected',
      gpsStatus: map['gpsStatus'] as String? ?? 'GPS Locked',
      lastSyncTime: map['lastSyncTime'] != null ? DateTime.parse(map['lastSyncTime'] as String) : null,
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : 37.77492,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : -122.41941,
      deviceName: map['deviceName'] as String? ?? 'VehiSafe',
      satellites: map['satellites'] as int? ?? 0,
      speed: map['speed'] != null ? (map['speed'] as num).toDouble() : 0.0,
    );
  }

  DeviceStatus copyWith({
    bool? isConnected,
    int? batteryPercent,
    DateTime? lastSeen,
    String? firmwareVersion,
    String? currentMode,
    String? networkStatus,
    String? gpsStatus,
    DateTime? lastSyncTime,
    double? latitude,
    double? longitude,
    String? deviceName,
    int? satellites,
    double? speed,
  }) {
    return DeviceStatus(
      isConnected: isConnected ?? this.isConnected,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      lastSeen: lastSeen ?? this.lastSeen,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      currentMode: currentMode ?? this.currentMode,
      networkStatus: networkStatus ?? this.networkStatus,
      gpsStatus: gpsStatus ?? this.gpsStatus,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      deviceName: deviceName ?? this.deviceName,
      satellites: satellites ?? this.satellites,
      speed: speed ?? this.speed,
    );
  }
}
