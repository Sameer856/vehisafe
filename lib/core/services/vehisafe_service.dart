import '../models/sensor_snapshot.dart';
import '../models/device_status.dart';
import '../models/alert_event.dart';
import '../models/emergency_contact.dart';
import '../models/vehicle_config.dart';

abstract class VehiSafeService {
  Stream<DeviceStatus> get deviceStatusStream;
  Stream<SensorSnapshot> get sensorStream;
  Stream<Map<String, dynamic>> get crashAlertStream; // Emits Map: { 'severityScore': double, 'severityLevel': String, 'sensorSnapshot': SensorSnapshot }

  Future<void> simulateCrash(String severityLevel);
  Future<List<AlertEvent>> getPrepopulatedHistory();

  // New pairing and configuration workflow APIs
  Future<List<String>> scanForDevices();
  Future<void> connectToDevice(String deviceName);
  Future<void> uploadConfiguration({
    required List<EmergencyContact> contacts,
    required VehicleConfig vehicleConfig,
    required String pin,
    required bool biometricEnabled,
    required String customMessage,
    required Function(double progress) onProgress,
  });
  Future<void> setDeviceMode(String mode);
  Future<void> resetDevice();
}
