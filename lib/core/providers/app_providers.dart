import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../models/vehicle_config.dart';
import '../models/emergency_contact.dart';
import '../models/sensor_snapshot.dart';
import '../models/device_status.dart';
import '../models/alert_event.dart';
import '../services/storage_service.dart';
import '../services/biometric_service.dart';
import '../services/notification_service.dart';
import '../services/vehisafe_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/mock_vehisafe_service.dart';

// --- Services Providers ---
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override storageServiceProvider in ProviderScope');
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final vehiSafeServiceProvider = Provider<VehiSafeService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final isConfigured = storage.getSettings().isOnboarded;
  final service = MockVehiSafeService(isConfigured: isConfigured);
  ref.onDispose(() => service.dispose());
  return service;
});

// --- App Settings State Notifier ---
class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final StorageService _storageService;

  AppSettingsNotifier(this._storageService) : super(_storageService.getSettings());

  Future<void> updateSettings({
    String? pin,
    bool? biometricEnabled,
    bool? developerMode,
    int? calibrationDrives,
    bool? isOnboarded,
    String? customMessage,
  }) async {
    String? pinHash;
    if (pin != null) {
      pinHash = sha256.convert(utf8.encode(pin)).toString();
    } else {
      pinHash = state.pinHash;
    }

    final newSettings = state.copyWith(
      pinHash: pinHash,
      biometricEnabled: biometricEnabled,
      developerMode: developerMode,
      calibrationDrives: calibrationDrives,
      isOnboarded: isOnboarded,
      customMessage: customMessage,
    );

    state = newSettings;
    await _storageService.saveSettings(newSettings);
  }

  bool verifyPin(String pin) {
    if (state.pinHash == null) return false;
    final hash = sha256.convert(utf8.encode(pin)).toString();
    return state.pinHash == hash;
  }

  Future<void> clearSettings() async {
    await _storageService.clearPin();
    state = AppSettings(
      pinHash: null,
      biometricEnabled: false,
      developerMode: false,
      calibrationDrives: 0,
      isOnboarded: false,
    );
    await _storageService.saveSettings(state);
  }
}

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return AppSettingsNotifier(storage);
});

// --- Vehicle Config State Notifier ---
class VehicleConfigNotifier extends StateNotifier<VehicleConfig?> {
  final StorageService _storageService;

  VehicleConfigNotifier(this._storageService) : super(_storageService.getVehicleConfig());

  Future<void> saveConfig(VehicleConfig config) async {
    state = config;
    await _storageService.saveVehicleConfig(config);
  }

  Future<void> clearConfig() async {
    state = null;
  }
}

final vehicleConfigProvider = StateNotifierProvider<VehicleConfigNotifier, VehicleConfig?>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return VehicleConfigNotifier(storage);
});

// --- Emergency Contacts State Notifier ---
class EmergencyContactsNotifier extends StateNotifier<List<EmergencyContact>> {
  final StorageService _storageService;

  EmergencyContactsNotifier(this._storageService) : super(_storageService.getEmergencyContacts());

  Future<void> addContact(String name, String phone) async {
    final newContact = EmergencyContact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      phoneNumber: phone,
    );
    final updated = [...state, newContact];
    state = updated;
    await _storageService.saveEmergencyContacts(updated);
  }

  Future<void> updateContact(EmergencyContact contact) async {
    final updated = state.map((c) => c.id == contact.id ? contact : c).toList();
    state = updated;
    await _storageService.saveEmergencyContacts(updated);
  }

  Future<void> deleteContact(String id) async {
    final updated = state.where((c) => c.id != id).toList();
    state = updated;
    await _storageService.saveEmergencyContacts(updated);
  }

  Future<void> clearContacts() async {
    state = [];
    await _storageService.saveEmergencyContacts([]);
  }
}

final emergencyContactsProvider = StateNotifierProvider<EmergencyContactsNotifier, List<EmergencyContact>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return EmergencyContactsNotifier(storage);
});

// --- Sensor & Device Streams ---
final deviceStatusProvider = StreamProvider<DeviceStatus>((ref) {
  final vehiSafe = ref.watch(vehiSafeServiceProvider);
  return vehiSafe.deviceStatusStream;
});

final sensorTelemetryProvider = StreamProvider<SensorSnapshot>((ref) {
  final vehiSafe = ref.watch(vehiSafeServiceProvider);
  return vehiSafe.sensorStream;
});

// --- Alert History State Notifier ---
class AlertHistoryNotifier extends StateNotifier<List<AlertEvent>> {
  final StorageService _storage;

  AlertHistoryNotifier(this._storage) : super([]) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = _storage.getAlertHistory();
    if (history.isEmpty) {
      // Pre-populate with mock values for demonstration
      final mockEvents = _storage.getAlertHistory();
      if (mockEvents.isEmpty) {
        // We'll populate mock history later or on first load if empty
      }
      state = history;
    } else {
      state = history;
    }
  }

  Future<void> addEvent(AlertEvent event) async {
    await _storage.addAlertEvent(event);
    state = [event, ...state];
  }

  Future<void> populateMockHistory(List<AlertEvent> mockList) async {
    for (var event in mockList) {
      await _storage.addAlertEvent(event);
    }
    state = _storage.getAlertHistory();
  }

  Future<void> clearHistory() async {
    await _storage.clearHistory();
    state = [];
  }
}

final alertHistoryProvider = StateNotifierProvider<AlertHistoryNotifier, List<AlertEvent>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return AlertHistoryNotifier(storage);
});

// --- Active Alert State & Notifier ---
class ActiveAlertState {
  final double severityScore;
  final String severityLevel; // LOW, MEDIUM, HIGH
  final int countdown;
  final SensorSnapshot sensorSnapshot;
  final List<EmergencyContact> contactsNotified;
  final DateTime timestamp;
  final bool isSending;
  final bool isSent;
  final String? videoUrl;
  final double latitude;
  final double longitude;
  final double? baseScore;
  final double? aiBonus;

  ActiveAlertState({
    required this.severityScore,
    required this.severityLevel,
    required this.countdown,
    required this.sensorSnapshot,
    required this.contactsNotified,
    required this.timestamp,
    this.isSending = false,
    this.isSent = false,
    this.videoUrl,
    required this.latitude,
    required this.longitude,
    this.baseScore,
    this.aiBonus,
  });

  ActiveAlertState copyWith({
    double? severityScore,
    String? severityLevel,
    int? countdown,
    SensorSnapshot? sensorSnapshot,
    List<EmergencyContact>? contactsNotified,
    DateTime? timestamp,
    bool? isSending,
    bool? isSent,
    String? videoUrl,
    double? latitude,
    double? longitude,
    double? baseScore,
    double? aiBonus,
  }) {
    return ActiveAlertState(
      severityScore: severityScore ?? this.severityScore,
      severityLevel: severityLevel ?? this.severityLevel,
      countdown: countdown ?? this.countdown,
      sensorSnapshot: sensorSnapshot ?? this.sensorSnapshot,
      contactsNotified: contactsNotified ?? this.contactsNotified,
      timestamp: timestamp ?? this.timestamp,
      isSending: isSending ?? this.isSending,
      isSent: isSent ?? this.isSent,
      videoUrl: videoUrl ?? this.videoUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      baseScore: baseScore ?? this.baseScore,
      aiBonus: aiBonus ?? this.aiBonus,
    );
  }
}

class ActiveAlertNotifier extends StateNotifier<ActiveAlertState?> {
  final Ref _ref;
  StreamSubscription? _crashSubscription;

  ActiveAlertNotifier(this._ref) : super(null) {
    // Listen to crash alert stream from physical/mock device
    final vehiSafe = _ref.read(vehiSafeServiceProvider);
    _crashSubscription = vehiSafe.crashAlertStream.listen((alertData) {
      triggerAlert(
        severityLevel: alertData['severityLevel'] as String,
        severityScore: alertData['severityScore'] as double,
        snapshot: alertData['sensorSnapshot'] as SensorSnapshot,
        videoUrl: alertData['videoUrl'] as String?,
        latitude: alertData['latitude'] as double?,
        longitude: alertData['longitude'] as double?,
        baseScore: alertData['baseScore'] as double?,
        aiBonus: alertData['aiBonus'] as double?,
      );
    });

    final bgService = FlutterBackgroundService();

    // Listen to background service signals (Single Source of Truth)
    bgService.on('onAlertStarted').listen((event) {
      if (event != null) {
        final contacts = _ref.read(emergencyContactsProvider);
        state = ActiveAlertState(
          severityScore: (event['severityScore'] as num).toDouble(),
          severityLevel: event['severityLevel'] as String,
          countdown: event['countdown'] as int,
          sensorSnapshot: SensorSnapshot(
            imuG: event['severityLevel'] == 'LOW' ? 2.4 : (event['severityLevel'] == 'MEDIUM' ? 4.8 : 8.5),
            pressureHpa: 1011.0,
            speedKmh: 68.4,
            gpsSignal: 94,
          ),
          contactsNotified: contacts,
          timestamp: DateTime.now(),
          latitude: (event['latitude'] as num).toDouble(),
          longitude: (event['longitude'] as num).toDouble(),
          baseScore: event['baseScore'] != null ? (event['baseScore'] as num).toDouble() : null,
          aiBonus: event['aiBonus'] != null ? (event['aiBonus'] as num).toDouble() : null,
        );
      }
    });

    bgService.on('onCountdownTick').listen((event) {
      if (event != null && state != null) {
        state = state!.copyWith(countdown: event['countdown'] as int);
      }
    });

    bgService.on('onAlertSending').listen((event) {
      if (state != null) {
        state = state!.copyWith(isSending: true);
      }
    });

    bgService.on('onAlertSent').listen((event) async {
      if (event != null && state != null) {
        // Create AlertEvent log
        final alertEvent = AlertEvent(
          id: 'alert_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: state!.timestamp,
          severityScore: (event['severityScore'] as num).toDouble(),
          severityLevel: event['severityLevel'] as String,
          outcome: 'Sent',
          gpsLat: state!.latitude,
          gpsLng: state!.longitude,
          sensorSnapshot: state!.sensorSnapshot,
          contactsNotified: state!.contactsNotified,
          videoUrl: event['videoUrl'] as String?,
          baseScore: event['baseScore'] != null ? (event['baseScore'] as num).toDouble() : null,
          aiBonus: event['aiBonus'] != null ? (event['aiBonus'] as num).toDouble() : null,
        );

        // Add to history
        await _ref.read(alertHistoryProvider.notifier).addEvent(alertEvent);

        state = state!.copyWith(
          isSending: false,
          isSent: true,
          videoUrl: event['videoUrl'] as String?,
          severityScore: (event['severityScore'] as num).toDouble(),
          baseScore: event['baseScore'] != null ? (event['baseScore'] as num).toDouble() : null,
          aiBonus: event['aiBonus'] != null ? (event['aiBonus'] as num).toDouble() : null,
        );
      }
    });

    bgService.on('onAlertCancelled').listen((event) async {
      if (state != null) {
        // Create cancelled AlertEvent log
        final alertEvent = AlertEvent(
          id: 'alert_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: state!.timestamp,
          severityScore: state!.severityScore,
          severityLevel: state!.severityLevel,
          outcome: 'Cancelled',
          gpsLat: state!.latitude,
          gpsLng: state!.longitude,
          sensorSnapshot: state!.sensorSnapshot,
          contactsNotified: state!.contactsNotified,
          videoUrl: state!.videoUrl,
          baseScore: state!.baseScore,
          aiBonus: state!.aiBonus,
        );

        // Add to history
        await _ref.read(alertHistoryProvider.notifier).addEvent(alertEvent);
      }

      state = null;
    });

    // Query active background alert upon startup
    bgService.invoke('queryActiveAlert');
    bgService.on('activeAlertResponse').listen((event) {
      if (event != null && event['active'] == true && state == null) {
        final contacts = _ref.read(emergencyContactsProvider);
        state = ActiveAlertState(
          severityScore: (event['severityScore'] as num).toDouble(),
          severityLevel: event['severityLevel'] as String,
          countdown: event['countdown'] as int,
          sensorSnapshot: SensorSnapshot(
            imuG: event['severityLevel'] == 'LOW' ? 2.4 : (event['severityLevel'] == 'MEDIUM' ? 4.8 : 8.5),
            pressureHpa: 1011.0,
            speedKmh: 68.4,
            gpsSignal: 94,
          ),
          contactsNotified: contacts,
          timestamp: DateTime.now(),
          latitude: (event['latitude'] as num).toDouble(),
          longitude: (event['longitude'] as num).toDouble(),
          baseScore: event['baseScore'] != null ? (event['baseScore'] as num).toDouble() : null,
          aiBonus: event['aiBonus'] != null ? (event['aiBonus'] as num).toDouble() : null,
          videoUrl: event['videoUrl'] as String?,
        );
      }
    });
  }

  void triggerAlert({
    required String severityLevel,
    required double severityScore,
    required SensorSnapshot snapshot,
    String? videoUrl,
    double? latitude,
    double? longitude,
    double? baseScore,
    double? aiBonus,
  }) {
    // Notify background service to start the alert sequence
    FlutterBackgroundService().invoke('startAlert', {
      'severityLevel': severityLevel,
      'latitude': latitude ?? 12.971598,
      'longitude': longitude ?? 77.594562,
    });
  }

  Future<void> sendAlert() async {
    // Delegate to background service
    FlutterBackgroundService().invoke('sendAlertNow');
  }

  Future<void> cancelAlert(String outcome) async {
    // Delegate to background service
    FlutterBackgroundService().invoke('cancelAlert');
  }

  void dismissAlert() {
    state = null;
  }

  @override
  void dispose() {
    _crashSubscription?.cancel();
    super.dispose();
  }
}

final activeAlertStateProvider = StateNotifierProvider<ActiveAlertNotifier, ActiveAlertState?>((ref) {
  return ActiveAlertNotifier(ref);
});
