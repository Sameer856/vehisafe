class VehicleConfig {
  final String type; // Car, SUV, Truck, Two-Wheeler
  final int year;

  VehicleConfig({
    required this.type,
    required this.year,
  });

  // Determines charging port: pre-2020 = 12V, 2020+ = USB-C
  String get chargingPort => year < 2020 ? '12V' : 'USB-C';

  // Two-wheeler disables barometer condition in detection logic
  bool get disableBarometer => type == 'Two-Wheeler';

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'year': year,
    };
  }

  factory VehicleConfig.fromMap(Map<dynamic, dynamic> map) {
    return VehicleConfig(
      type: map['type'] as String,
      year: map['year'] as int,
    );
  }

  VehicleConfig copyWith({
    String? type,
    int? year,
  }) {
    return VehicleConfig(
      type: type ?? this.type,
      year: year ?? this.year,
    );
  }
}
