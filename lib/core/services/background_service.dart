import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';

class BackgroundServiceManager {
  static const String channelId = 'vehisafe_bg_channel';
  static const int notificationId = 888;

  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Create Notification Channel for Android Foreground Service
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelId,
        'VehiSafe Background Monitor',
        description: 'Handles background telemetry polling from the VehiSafe board',
        importance: Importance.low,
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: channelId,
        initialNotificationTitle: 'VehiSafe Active Monitoring',
        initialNotificationContent: 'Connecting to VehiSafe (192.168.100.100:8080)...',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );

    await service.startService();
    debugPrint('Persistent Foreground Service initialized and started.');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  debugPrint('[BACKGROUND SERVICE] Isolate started.');

  final notificationService = NotificationService();
  await notificationService.init();

  Timer? pollingTimer;
  Timer? countdownTimer;

  bool isAlertActive = false;
  int countdown = 10;
  String severityLevel = 'HIGH';
  double baseScore = 9.4;
  double aiBonus = 0.0;
  double severityScore = 9.4;
  String? videoUrl;
  double latitude = 12.971598;
  double longitude = 77.594562;

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // Helper to start the alert sequence
  void startAlert(String severity, double lat, double lng) async {
    if (isAlertActive) return;
    isAlertActive = true;
    severityLevel = severity;
    latitude = lat;
    longitude = lng;
    countdown = severity == 'LOW' ? 30 : (severity == 'MEDIUM' ? 15 : 10);
    baseScore = severity == 'LOW' ? 3.5 : (severity == 'MEDIUM' ? 6.2 : 9.4);
    aiBonus = 0.0;
    severityScore = baseScore;
    videoUrl = null;

    debugPrint('[BACKGROUND SERVICE] Starting Alert Countdown: $countdown seconds');

    // Notify main app
    service.invoke('onAlertStarted', {
      'severityLevel': severityLevel,
      'countdown': countdown,
      'latitude': latitude,
      'longitude': longitude,
      'baseScore': baseScore,
      'aiBonus': aiBonus,
      'severityScore': severityScore,
    });

    // Show heads up notification
    await notificationService.showCrashAlert(severityLevel, countdown);

    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (countdown > 1) {
        countdown--;
        service.invoke('onCountdownTick', {'countdown': countdown});
        await notificationService.showCrashAlert(severityLevel, countdown);
      } else {
        timer.cancel();
        // Dispatch the alert!
        debugPrint('[BACKGROUND SERVICE] Countdown reached 0. Dispatching alert...');
        
        service.invoke('onAlertSending');

        // Hit local Pi simulation endpoint or fall back to Firebase Cloud Trigger
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 3);
          final request = await client.getUrl(Uri.parse('http://192.168.100.100:8080/simulate?severity=$severityLevel'));
          await request.close();
        } catch (e) {
          debugPrint('[BACKGROUND SERVICE] Pi unreachable at 192.168.100.100: $e');
          // Post simulation trigger to Firebase RTDB for cloud alert fallback
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
          } catch (fe) {
            debugPrint('[BACKGROUND SERVICE] Firebase simulation trigger post failed: $fe');
          }
          aiBonus = 1.5; // fallback
          severityScore = baseScore + aiBonus;
          videoUrl = 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
        }

        // Retrieve the cloud video link and scoring details from Firebase RTDB
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
              severityScore = baseScore + aiBonus;
              debugPrint('[BACKGROUND SERVICE] Successfully loaded alert video from Firebase Storage: $videoUrl');
            } else {
              debugPrint('[BACKGROUND SERVICE] Firebase alerts data is empty or invalid (null).');
            }
          }
        } catch (err) {
          debugPrint('[BACKGROUND SERVICE] Firebase alert retrieval failed: $err');
        }

        // Show alert sent notification
        await notificationService.cancelCrashAlert();
        await notificationService.showAlertSentNotification();

        service.invoke('onAlertSent', {
          'severityLevel': severityLevel,
          'severityScore': severityScore,
          'baseScore': baseScore,
          'aiBonus': aiBonus,
          'videoUrl': videoUrl,
        });

        isAlertActive = false;
      }
    });
  }

  // Helper to cancel the alert
  void cancelAlert() async {
    if (!isAlertActive) return;
    isAlertActive = false;
    countdownTimer?.cancel();
    await notificationService.cancelCrashAlert();
    service.invoke('onAlertCancelled');
    debugPrint('[BACKGROUND SERVICE] Alert cancelled.');
  }

  // Listeners from main app
  service.on('startAlert').listen((event) {
    if (event != null) {
      final String severity = event['severityLevel'] as String? ?? 'HIGH';
      final double lat = event['latitude'] as double? ?? 12.971598;
      final double lng = event['longitude'] as double? ?? 77.594562;
      startAlert(severity, lat, lng);
    }
  });

  service.on('cancelAlert').listen((event) {
    cancelAlert();
  });

  service.on('sendAlertNow').listen((event) async {
    // Skip remaining countdown and trigger immediately
    countdownTimer?.cancel();
    countdown = 1;
    // We let the timer callback or helper run the dispatch logic immediately
    isAlertActive = false; // reset flag for starting
    startAlert(severityLevel, latitude, longitude);
  });

  service.on('queryActiveAlert').listen((event) {
    if (isAlertActive) {
      service.invoke('activeAlertResponse', {
        'active': true,
        'countdown': countdown,
        'severityLevel': severityLevel,
        'latitude': latitude,
        'longitude': longitude,
        'baseScore': baseScore,
        'aiBonus': aiBonus,
        'severityScore': severityScore,
        'videoUrl': videoUrl,
      });
    } else {
      service.invoke('activeAlertResponse', {'active': false});
    }
  });

  service.on('stopService').listen((event) {
    pollingTimer?.cancel();
    countdownTimer?.cancel();
    service.stopSelf();
    debugPrint('[BACKGROUND SERVICE] Isolate stopped.');
  });

  // Background HTTP Polling Loop
  pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 1);
      
      var requestUrl = 'http://192.168.100.100:8080/status';
      var isCloud = false;
      HttpClientRequest request;
      
      try {
        request = await client.getUrl(Uri.parse(requestUrl));
        final response = await request.close();
        if (response.statusCode != 200) throw Exception();
      } catch (e) {
        // Fallback to Firebase
        requestUrl = 'https://vehisafe-alert-default-rtdb.firebaseio.com/device_status/VH001.json';
        request = await client.getUrl(Uri.parse(requestUrl));
        isCloud = true;
      }
      
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = json.decode(responseBody);

        final int sats = (data['satellites'] ?? data['satellites'] ?? 0) as int;
        final double speed = ((data['speed_kmh'] ?? data['speed'] ?? 0.0) as num).toDouble();
        final String gpsStatus = (data['gps_status'] ?? data['gpsStatus'] ?? 'Acquiring') as String;

        // Update active notification text with live telemetry
        if (service is AndroidServiceInstance && !isAlertActive) {
          service.setForegroundNotificationInfo(
            title: isCloud ? 'VehiSafe: Cloud Monitor' : 'VehiSafe: Active Shield Monitor',
            content: 'GPS: $gpsStatus | Satellites: $sats | Speed: ${speed.toStringAsFixed(1)} km/h',
          );
        }

        // Check for hardware trigger flag or cloud active alert
        final bool isCrashTriggered = (data['crash_triggered'] == true) || 
            (isCloud && data['currentMode'] == 'Alert');
            
        if (isCrashTriggered && !isAlertActive) {
          debugPrint('[BACKGROUND SERVICE] CRASH DETECTED!');
          startAlert('HIGH', (data['latitude'] ?? data['lat'] ?? 12.971598) as double, (data['longitude'] ?? data['lng'] ?? 77.594562) as double);
        }
      }
    } catch (e) {
      if (service is AndroidServiceInstance && !isAlertActive) {
        service.setForegroundNotificationInfo(
          title: 'VehiSafe: Searching...',
          content: 'Searching for Pi (192.168.100.100) & Firebase cloud...',
        );
      }
    }
  });
}
