import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/sensor_snapshot.dart';
import '../models/device_status.dart';
import '../models/alert_event.dart';
import '../models/emergency_contact.dart';
import '../models/vehicle_config.dart';
import 'vehisafe_service.dart';

class MockVehiSafeService implements VehiSafeService {
  final _deviceStatusController = StreamController<DeviceStatus>.broadcast();
  final _sensorStreamController = StreamController<SensorSnapshot>.broadcast();
  final _crashAlertController = StreamController<Map<String, dynamic>>.broadcast();
  
  Timer? _sensorTimer;

  
  bool _isConnected = false;
  bool _isConfigured;
  String _activeLocalIp = '192.168.4.1'; // Default to hotspot IP
  
  @override
  String get activeLocalIp => _activeLocalIp;
  
  String _currentMode = 'Monitoring';
  String _networkStatus = 'LTE Connected';
  String _gpsStatus = 'GPS Locked';
  int _batteryPercent = 95;
  double _latitude = 37.77492;
  double _longitude = -122.41941;
  DateTime? _lastSyncTime;
  int _satellites = 0;
  double _speed = 0.0;


  MockVehiSafeService({bool isConfigured = false}) : _isConfigured = isConfigured {
    _initDevice();
  }

  void _initDevice() {
    if (_isConfigured) {
      _currentMode = 'Monitoring';
      _networkStatus = 'LTE Connected';
      _gpsStatus = 'GPS Locked';
      _isConnected = true;
      _lastSyncTime = DateTime.now();
      _startSensorStreaming();
    } else {
      _currentMode = 'Configuration';
      _networkStatus = 'Local WiFi';
      _gpsStatus = 'No Signal';
      _isConnected = false;
    }
    _publishStatus();
  }

  void _publishStatus() {
    if (_deviceStatusController.isClosed) return;
    _deviceStatusController.add(DeviceStatus(
      isConnected: _isConnected,
      batteryPercent: _batteryPercent,
      firmwareVersion: 'v1.2.0-rc1',
      lastSeen: DateTime.now(),
      currentMode: _currentMode,
      networkStatus: _networkStatus,
      gpsStatus: _gpsStatus,
      lastSyncTime: _lastSyncTime,
      latitude: _latitude,
      longitude: _longitude,
      deviceName: 'VehiSafe',
      satellites: _satellites,
      speed: _speed,
    ));
  }

  void _startSensorStreaming() {
    _sensorTimer?.cancel();
    _sensorTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isConnected || _currentMode != 'Monitoring') return;

      // Attempt to fetch real telemetry from local Pi or Firebase cloud
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 1);
        
        var requestUrl = 'http://$_activeLocalIp:8080/status';
        var isCloudFallback = false;
        HttpClientRequest request;
        
        try {
          request = await client.getUrl(Uri.parse(requestUrl));
          final response = await request.close();
          if (response.statusCode != 200) throw Exception();
        } catch (e) {
          // Fallback to Firebase Realtime Database
          requestUrl = 'https://vehisafe-alert-default-rtdb.firebaseio.com/device_status/VH001.json';
          request = await client.getUrl(Uri.parse(requestUrl));
          isCloudFallback = true;
        }
        
        final response = await request.close();
        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final Map<String, dynamic> data = json.decode(responseBody);
          
          _latitude = ((data['latitude'] ?? 0.0) as num).toDouble();
          _longitude = ((data['longitude'] ?? 0.0) as num).toDouble();
          _gpsStatus = (data['gps_status'] ?? data['gpsStatus'] ?? 'GPS Acquiring') as String;
          _speed = ((data['speed_kmh'] ?? data['speed'] ?? 0.0) as num).toDouble();
          _satellites = (data['satellites'] ?? data['satellites'] ?? 0) as int;
          
          _lastSyncTime = DateTime.now();
          _publishStatus();
          
          // Read sensor payload if present
          final sensorData = data['sensors'] ?? {};
          final double imuG = (sensorData['accel_z'] != null) 
              ? (sensorData['accel_z'] as num).toDouble() 
              : 1.0;
          final double pressure = (sensorData['baro_pressure_hpa'] ?? sensorData['pressure_hpa'] ?? 1013.2) as double;
          
          _sensorStreamController.add(SensorSnapshot(
            imuG: imuG,
            pressureHpa: pressure,
            speedKmh: _speed,
            gpsSignal: _satellites > 0 ? min(100, _satellites * 10) : 0,
          ));

          // Check if hardware button or cloud alert triggered a crash simulation
          final bool isCrashTriggered = (data['crash_triggered'] == true) || 
              (isCloudFallback && data['currentMode'] == 'Alert');
              
          if (isCrashTriggered) {
            debugPrint('Crash Trigger detected via status payload!');
            if (_currentMode != 'Alert') {
              simulateCrash('HIGH');
            }
          }
          return; // Skip mock generation since we successfully got real data
        }
      } catch (e) {
        // Silently fail and run fallback mock generation
        debugPrint('Telemetry status fetch failed: $e');
      }

      // Mock Fallback: When the hardware device status fetch fails, mark it offline.
      // We zero out current speed and satellites, but preserve the last known GPS coordinates and sync time.
      _isConnected = false;
      _networkStatus = 'Offline';
      _gpsStatus = 'No Signal';
      _speed = 0.0;
      _satellites = 0;
      
      _publishStatus();

      _sensorStreamController.add(SensorSnapshot(
        imuG: 0.0,
        pressureHpa: 0.0,
        speedKmh: 0.0,
        gpsSignal: 0,
      ));
    });
  }

  @override
  Stream<DeviceStatus> get deviceStatusStream => _deviceStatusController.stream;

  @override
  Stream<SensorSnapshot> get sensorStream => _sensorStreamController.stream;

  @override
  Stream<Map<String, dynamic>> get crashAlertStream => _crashAlertController.stream;

  @override
  Future<void> simulateCrash(String severityLevel) async {
    double score;
    double imuG;
    double pressureDrop;

    switch (severityLevel) {
      case 'LOW':
        score = 3.5;
        imuG = 2.4;
        pressureDrop = 0.5;
        break;
      case 'MEDIUM':
        score = 6.2;
        imuG = 4.8;
        pressureDrop = 1.8;
        break;
      case 'HIGH':
      default:
        score = 9.4;
        imuG = 8.5;
        pressureDrop = 4.2;
        break;
    }

    final double baseScore = score;
    double aiBonus = 0.0;

    final crashSnapshot = SensorSnapshot(
      imuG: imuG,
      pressureHpa: 1013.2 - pressureDrop,
      speedKmh: 68.4,
      gpsSignal: 94,
    );

    // Update state to alert active
    _currentMode = 'Alert';
    _publishStatus();

    String videoUrl = 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
    
    // Hit the real VehiSafe Edge AI server or fall back to Firebase Cloud Trigger
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      
      // Hitting local simulate endpoint on Pi
      final request = await client.getUrl(Uri.parse('http://$_activeLocalIp:8080/simulate?severity=$severityLevel'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        debugPrint('Local Pi Response: $responseBody');
      }
    } catch (e) {
      debugPrint('Local Pi unreachable at $_activeLocalIp. Posting simulation trigger to cloud. Details: $e');
      // Trigger simulation over the cloud by PUTting directly to Firebase RTDB for the device
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final request = await client.putUrl(Uri.parse('https://vehisafe-alert-default-rtdb.firebaseio.com/simulate_trigger/VH001.json'));
        request.headers.contentType = ContentType.json;
        final payload = json.encode({
          'severity': severityLevel,
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000
        });
        request.add(utf8.encode(payload));
        await request.close();
        debugPrint('Firebase Cloud Simulation trigger posted successfully.');
      } catch (fe) {
        debugPrint('Firebase Cloud Simulation trigger failed: $fe');
      }
      
      // Setup typical mock values for simulation
      aiBonus = 1.5;
      score += aiBonus;
    }

    // Attempt to pull latest alert metadata and storage videoUrl from Firebase RTDB
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(Uri.parse('https://vehisafe-alert-default-rtdb.firebaseio.com/alerts/VH001.json'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final dynamic decoded = json.decode(responseBody);
        if (decoded is Map<String, dynamic>) {
          final String? cloudVideoUrl = decoded['videoUrl'];
          if (cloudVideoUrl != null && cloudVideoUrl.isNotEmpty) {
            videoUrl = cloudVideoUrl;
          }
          aiBonus = (decoded['aiBonus'] as num?)?.toDouble() ?? aiBonus;
          score = baseScore + aiBonus;
          debugPrint('Successfully loaded alert video from Firebase Storage: $videoUrl');
        } else {
          debugPrint('Firebase alerts data is empty or invalid (null).');
        }
      }
    } catch (firebaseErr) {
      debugPrint('Failed to query Firebase cloud alert URL: $firebaseErr');
    }

    _crashAlertController.add({
      'severityScore': score,
      'severityLevel': severityLevel,
      'sensorSnapshot': crashSnapshot,
      'videoUrl': videoUrl,
      'latitude': _latitude,
      'longitude': _longitude,
      'baseScore': baseScore,
      'aiBonus': aiBonus,
    });
  }

  @override
  Future<List<AlertEvent>> getPrepopulatedHistory() async {
    final contacts = [
      EmergencyContact(id: 'c1', name: 'John Doe', phoneNumber: '+1234567890'),
      EmergencyContact(id: 'c2', name: 'Sarah Smith', phoneNumber: '+9876543210'),
    ];

    return [
      AlertEvent(
        id: 'mock_alert_1',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        severityScore: 3.2,
        severityLevel: 'LOW',
        outcome: 'Cancelled',
        gpsLat: 37.7749,
        gpsLng: -122.4194,
        sensorSnapshot: SensorSnapshot(imuG: 2.1, pressureHpa: 1011.2, speedKmh: 24.5, gpsSignal: 85),
        contactsNotified: contacts,
        baseScore: 3.0,
        aiBonus: 0.2,
      ),
      AlertEvent(
        id: 'mock_alert_2',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        severityScore: 6.8,
        severityLevel: 'MEDIUM',
        outcome: 'Sent',
        gpsLat: 37.7892,
        gpsLng: -122.4018,
        sensorSnapshot: SensorSnapshot(imuG: 4.8, pressureHpa: 1008.5, speedKmh: 58.0, gpsSignal: 92),
        contactsNotified: contacts,
        baseScore: 5.5,
        aiBonus: 1.3,
      ),
      AlertEvent(
        id: 'mock_alert_3',
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
        severityScore: 9.6,
        severityLevel: 'HIGH',
        outcome: 'Sent',
        gpsLat: 37.8024,
        gpsLng: -122.4058,
        sensorSnapshot: SensorSnapshot(imuG: 9.2, pressureHpa: 1004.1, speedKmh: 84.2, gpsSignal: 99),
        contactsNotified: contacts,
        baseScore: 8.0,
        aiBonus: 1.6,
      ),
    ];
  }

  // --- pairing/connectivity APIs ---

  @override
  Future<List<String>> scanForDevices() async {
    // Minimal delay just for smooth visual transition
    await Future.delayed(const Duration(milliseconds: 500));
    return ['VehiSafe'];
  }

  @override
  Future<void> connectToDevice(String deviceName) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _isConnected = true;
    _networkStatus = 'Local WiFi';
    _currentMode = 'Configuration';
    
    // Probe local network to find active Pi IP (Wi-Fi hotspot vs USB Ethernet gadget)
    final targetIps = ['192.168.4.1', '192.168.100.100'];
    for (final ip in targetIps) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 1);
        final request = await client.getUrl(Uri.parse('http://$ip:8080/status'));
        final response = await request.close();
        if (response.statusCode == 200) {
          _activeLocalIp = ip;
          debugPrint('[VEHISAFE SERVICE] Found active Pi IP: $_activeLocalIp');
          break;
        }
      } catch (e) {
        debugPrint('[VEHISAFE SERVICE] Probe failed for Pi IP $ip: $e');
      }
    }
    
    _publishStatus();
  }

  @override
  Future<void> uploadConfiguration({
    required List<EmergencyContact> contacts,
    required VehicleConfig vehicleConfig,
    required String pin,
    required bool biometricEnabled,
    required String customMessage,
    required Function(double progress) onProgress,
  }) async {
    onProgress(0.1);

    final c1 = contacts.isNotEmpty ? contacts[0].phoneNumber : '';
    final c2 = contacts.length > 1 ? contacts[1].phoneNumber : '';
    final c3 = contacts.length > 2 ? contacts[2].phoneNumber : '';

    bool firebaseSuccess = false;
    String lastFirebaseError = 'None';
    String lastLocalError = 'None';

    // 1. Sync configuration to Firebase RTDB over the internet
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      
      onProgress(0.2);
      final request = await client.putUrl(Uri.parse('https://vehisafe-alert-default-rtdb.firebaseio.com/device_config/VH001.json'));
      request.headers.contentType = ContentType.json;
      
      final payload = json.encode({
        'contact1': c1,
        'contact2': c2,
        'contact3': c3,
        'vehicle': vehicleConfig.type,
        'custom_msg': customMessage,
        'configured': true,
      });
      request.add(utf8.encode(payload));
      
      onProgress(0.4);
      final response = await request.close();
      if (response.statusCode == 200 || response.statusCode == 204) {
        firebaseSuccess = true;
        debugPrint('Cloud Config sync successful.');
      } else {
        debugPrint('Cloud Config sync returned status: ${response.statusCode}');
        lastFirebaseError = 'Status ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('Cloud Config sync failed: $e');
      lastFirebaseError = e.toString();
    }

    onProgress(0.5);

    // 2. Perform local HTTP POST to save configurations on ESP32/Pi (as fallback/local network control)
    bool localSuccess = false;
    final targetIps = [_activeLocalIp, _activeLocalIp == '192.168.4.1' ? '192.168.100.100' : '192.168.4.1'];
    
    List<String> localErrors = [];
    for (final ip in targetIps) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5); // Extended timeout for mobile handshakes

        final body = 'contact1=${Uri.encodeQueryComponent(c1)}'
            '&contact2=${Uri.encodeQueryComponent(c2)}'
            '&contact3=${Uri.encodeQueryComponent(c3)}'
            '&vehicle=${Uri.encodeQueryComponent(vehicleConfig.type)}'
            '&custom_msg=${Uri.encodeQueryComponent(customMessage)}';

        final bodyBytes = utf8.encode(body);

        onProgress(0.6);
        final request = await client.postUrl(Uri.parse('http://$ip:8080/save'));
        request.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
        request.contentLength = bodyBytes.length;
        
        onProgress(0.7);
        request.add(bodyBytes);

        onProgress(0.8);
        final response = await request.close();
        onProgress(0.9);

        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          debugPrint('Pi Hardware Config Response from $ip: $responseBody');
          _activeLocalIp = ip; // Lock onto the working IP
          localSuccess = true;
          break;
        } else {
          localErrors.add('$ip: Status ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Pi Hardware Local Config unreachable at $ip: $e');
        localErrors.add('$ip: $e');
      }
    }
    
    if (localErrors.isNotEmpty) {
      lastLocalError = localErrors.join(' | ');
    }

    onProgress(1.0);

    // Sync succeeds if either cloud or local succeeded
    if (!firebaseSuccess && !localSuccess) {
      throw Exception('Could not sync configuration.\n\nCloud Error: $lastFirebaseError\n\nLocal Error: $lastLocalError');
    }

    _isConfigured = true;
    _currentMode = 'Monitoring';
    _networkStatus = firebaseSuccess ? 'LTE Connected' : 'Local WiFi';
    _gpsStatus = 'GPS Locked';
    _isConnected = true;
    _lastSyncTime = DateTime.now();
    _publishStatus();
    _startSensorStreaming();
  }

  @override
  Future<void> setDeviceMode(String mode) async {
    _currentMode = mode;
    _publishStatus();
  }

  @override
  Future<void> resetDevice() async {
    _sensorTimer?.cancel();
    
    _isConfigured = false;
    _isConnected = false;
    _currentMode = 'Configuration';
    _networkStatus = 'Local WiFi';
    _gpsStatus = 'No Signal';
    _batteryPercent = 95;
    
    _publishStatus();
  }

  void dispose() {
    _sensorTimer?.cancel();
    _deviceStatusController.close();
    _sensorStreamController.close();
    _crashAlertController.close();
  }
}
