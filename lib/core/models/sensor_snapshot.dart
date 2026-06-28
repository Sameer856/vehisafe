class SensorSnapshot {
  final double imuG;
  final double pressureHpa;
  final double speedKmh;
  final int gpsSignal; // GPS signal strength (e.g. out of 5 stars, or in dBm, let's use 0-100 or number of satellites)

  SensorSnapshot({
    required this.imuG,
    required this.pressureHpa,
    required this.speedKmh,
    required this.gpsSignal,
  });

  Map<String, dynamic> toMap() {
    return {
      'imuG': imuG,
      'pressureHpa': pressureHpa,
      'speedKmh': speedKmh,
      'gpsSignal': gpsSignal,
    };
  }

  factory SensorSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return SensorSnapshot(
      imuG: (map['imuG'] as num).toDouble(),
      pressureHpa: (map['pressureHpa'] as num).toDouble(),
      speedKmh: (map['speedKmh'] as num).toDouble(),
      gpsSignal: map['gpsSignal'] as int,
    );
  }

  SensorSnapshot copyWith({
    double? imuG,
    double? pressureHpa,
    double? speedKmh,
    int? gpsSignal,
  }) {
    return SensorSnapshot(
      imuG: imuG ?? this.imuG,
      pressureHpa: pressureHpa ?? this.pressureHpa,
      speedKmh: speedKmh ?? this.speedKmh,
      gpsSignal: gpsSignal ?? this.gpsSignal,
    );
  }
}
