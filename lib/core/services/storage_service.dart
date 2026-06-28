import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/emergency_contact.dart';
import '../models/vehicle_config.dart';
import '../models/app_settings.dart';
import '../models/alert_event.dart';

class StorageService {
  final SharedPreferences _prefs;
  late final Box _historyBox;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    await Hive.initFlutter();
    final prefs = await SharedPreferences.getInstance();
    final service = StorageService(prefs);
    service._historyBox = await Hive.openBox('alerts_history');
    return service;
  }

  // --- AppSettings ---
  static const _keyPinHash = 'vehisafe_pin_hash';
  static const _keyBiometricEnabled = 'vehisafe_biometric_enabled';
  static const _keyDeveloperMode = 'vehisafe_developer_mode';
  static const _keyCalibrationDrives = 'vehisafe_calibration_drives';
  static const _keyIsOnboarded = 'vehisafe_is_onboarded';
  static const _keyCustomMessage = 'vehisafe_custom_message';

  AppSettings getSettings() {
    return AppSettings(
      pinHash: _prefs.getString(_keyPinHash),
      biometricEnabled: _prefs.getBool(_keyBiometricEnabled) ?? false,
      developerMode: _prefs.getBool(_keyDeveloperMode) ?? false,
      calibrationDrives: _prefs.getInt(_keyCalibrationDrives) ?? 0,
      isOnboarded: _prefs.getBool(_keyIsOnboarded) ?? false,
      customMessage: _prefs.getString(_keyCustomMessage) ?? 'Emergency Alert: Vehicle experienced a crash.',
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    if (settings.pinHash != null) {
      await _prefs.setString(_keyPinHash, settings.pinHash!);
    } else {
      await _prefs.remove(_keyPinHash);
    }
    await _prefs.setBool(_keyBiometricEnabled, settings.biometricEnabled);
    await _prefs.setBool(_keyDeveloperMode, settings.developerMode);
    await _prefs.setInt(_keyCalibrationDrives, settings.calibrationDrives);
    await _prefs.setBool(_keyIsOnboarded, settings.isOnboarded);
    await _prefs.setString(_keyCustomMessage, settings.customMessage);
  }

  Future<void> clearPin() async {
    await _prefs.remove(_keyPinHash);
  }

  // --- VehicleConfig ---
  static const _keyVehicleType = 'vehisafe_vehicle_type';
  static const _keyVehicleYear = 'vehisafe_vehicle_year';

  VehicleConfig? getVehicleConfig() {
    final type = _prefs.getString(_keyVehicleType);
    final year = _prefs.getInt(_keyVehicleYear);
    if (type == null || year == null) return null;
    return VehicleConfig(type: type, year: year);
  }

  Future<void> saveVehicleConfig(VehicleConfig config) async {
    await _prefs.setString(_keyVehicleType, config.type);
    await _prefs.setInt(_keyVehicleYear, config.year);
  }

  // --- EmergencyContacts ---
  static const _keyContacts = 'vehisafe_emergency_contacts';

  List<EmergencyContact> getEmergencyContacts() {
    final jsonStr = _prefs.getString(_keyContacts);
    if (jsonStr == null) return [];
    try {
      final List decoded = json.decode(jsonStr);
      return decoded.map((c) => EmergencyContact.fromMap(c)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEmergencyContacts(List<EmergencyContact> contacts) async {
    final list = contacts.map((c) => c.toMap()).toList();
    await _prefs.setString(_keyContacts, json.encode(list));
  }

  // --- AlertEvent History (Hive) ---
  List<AlertEvent> getAlertHistory() {
    final List<AlertEvent> history = [];
    for (var key in _historyBox.keys) {
      final data = _historyBox.get(key);
      if (data is Map) {
        try {
          history.add(AlertEvent.fromMap(data));
        } catch (_) {
          // ignore corrupted data entries
        }
      }
    }
    // Sort descending by timestamp
    history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return history;
  }

  Future<void> addAlertEvent(AlertEvent event) async {
    await _historyBox.put(event.id, event.toMap());
  }

  Future<void> clearHistory() async {
    await _historyBox.clear();
  }

  Future<void> resetAll() async {
    await _prefs.clear();
    await _historyBox.clear();
  }
}
