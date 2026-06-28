import 'package:flutter_test/flutter_test.dart';
import 'package:vehisafe/core/models/vehicle_config.dart';

void main() {
  group('VehicleConfig Tests', () {
    test('Pre-2020 vehicles should have 12V charging port', () {
      final config = VehicleConfig(type: 'Car', year: 2019);
      expect(config.chargingPort, equals('12V'));
    });

    test('2020 and newer vehicles should have USB-C charging port', () {
      final config = VehicleConfig(type: 'Car', year: 2020);
      expect(config.chargingPort, equals('USB-C'));
    });

    test('Two-Wheeler vehicles should disable barometer', () {
      final config = VehicleConfig(type: 'Two-Wheeler', year: 2022);
      expect(config.disableBarometer, isTrue);
    });

    test('Other vehicles should not disable barometer', () {
      final config = VehicleConfig(type: 'SUV', year: 2022);
      expect(config.disableBarometer, isFalse);
    });
  });
}
