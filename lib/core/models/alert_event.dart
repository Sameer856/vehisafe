import 'emergency_contact.dart';
import 'sensor_snapshot.dart';

class AlertEvent {
  final String id;
  final DateTime timestamp;
  final double severityScore;
  final String severityLevel; // LOW, MEDIUM, HIGH
  final String outcome; // Sent, Cancelled, False Alarm
  final double gpsLat;
  final double gpsLng;
  final SensorSnapshot sensorSnapshot;
  final List<EmergencyContact> contactsNotified;
  final String? videoUrl;
  final double? baseScore;
  final double? aiBonus;

  AlertEvent({
    required this.id,
    required this.timestamp,
    required this.severityScore,
    required this.severityLevel,
    required this.outcome,
    required this.gpsLat,
    required this.gpsLng,
    required this.sensorSnapshot,
    required this.contactsNotified,
    this.videoUrl,
    this.baseScore,
    this.aiBonus,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'severityScore': severityScore,
      'severityLevel': severityLevel,
      'outcome': outcome,
      'gpsLat': gpsLat,
      'gpsLng': gpsLng,
      'sensorSnapshot': sensorSnapshot.toMap(),
      'contactsNotified': contactsNotified.map((c) => c.toMap()).toList(),
      'videoUrl': videoUrl,
      'baseScore': baseScore,
      'aiBonus': aiBonus,
    };
  }

  factory AlertEvent.fromMap(Map<dynamic, dynamic> map) {
    return AlertEvent(
      id: map['id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      severityScore: (map['severityScore'] as num).toDouble(),
      severityLevel: map['severityLevel'] as String,
      outcome: map['outcome'] as String,
      gpsLat: (map['gpsLat'] as num).toDouble(),
      gpsLng: (map['gpsLng'] as num).toDouble(),
      sensorSnapshot: SensorSnapshot.fromMap(map['sensorSnapshot'] as Map),
      contactsNotified: (map['contactsNotified'] as List)
          .map((c) => EmergencyContact.fromMap(c as Map))
          .toList(),
      videoUrl: map['videoUrl'] as String?,
      baseScore: map['baseScore'] != null ? (map['baseScore'] as num).toDouble() : null,
      aiBonus: map['aiBonus'] != null ? (map['aiBonus'] as num).toDouble() : null,
    );
  }

  AlertEvent copyWith({
    String? id,
    DateTime? timestamp,
    double? severityScore,
    String? severityLevel,
    String? outcome,
    double? gpsLat,
    double? gpsLng,
    SensorSnapshot? sensorSnapshot,
    List<EmergencyContact>? contactsNotified,
    String? videoUrl,
    double? baseScore,
    double? aiBonus,
  }) {
    return AlertEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      severityScore: severityScore ?? this.severityScore,
      severityLevel: severityLevel ?? this.severityLevel,
      outcome: outcome ?? this.outcome,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
      sensorSnapshot: sensorSnapshot ?? this.sensorSnapshot,
      contactsNotified: contactsNotified ?? this.contactsNotified,
      videoUrl: videoUrl ?? this.videoUrl,
      baseScore: baseScore ?? this.baseScore,
      aiBonus: aiBonus ?? this.aiBonus,
    );
  }
}
