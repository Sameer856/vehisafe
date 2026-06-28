class AppSettings {
  final String? pinHash;
  final bool biometricEnabled;
  final bool developerMode;
  final int calibrationDrives; // complete 2 drives to finish calibration
  final bool isOnboarded;
  final String customMessage;

  AppSettings({
    this.pinHash,
    required this.biometricEnabled,
    required this.developerMode,
    required this.calibrationDrives,
    required this.isOnboarded,
    this.customMessage = 'Emergency Alert: Vehicle experienced a crash.',
  });

  Map<String, dynamic> toMap() {
    return {
      'pinHash': pinHash,
      'biometricEnabled': biometricEnabled,
      'developerMode': developerMode,
      'calibrationDrives': calibrationDrives,
      'isOnboarded': isOnboarded,
      'customMessage': customMessage,
    };
  }

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) {
    return AppSettings(
      pinHash: map['pinHash'] as String?,
      biometricEnabled: map['biometricEnabled'] as bool? ?? false,
      developerMode: map['developerMode'] as bool? ?? false,
      calibrationDrives: map['calibrationDrives'] as int? ?? 0,
      isOnboarded: map['isOnboarded'] as bool? ?? false,
      customMessage: map['customMessage'] as String? ?? 'Emergency Alert: Vehicle experienced a crash.',
    );
  }

  AppSettings copyWith({
    String? pinHash,
    bool? biometricEnabled,
    bool? developerMode,
    int? calibrationDrives,
    bool? isOnboarded,
    String? customMessage,
  }) {
    return AppSettings(
      pinHash: pinHash ?? this.pinHash,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      developerMode: developerMode ?? this.developerMode,
      calibrationDrives: calibrationDrives ?? this.calibrationDrives,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      customMessage: customMessage ?? this.customMessage,
    );
  }
}
