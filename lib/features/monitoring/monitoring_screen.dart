import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/models/sensor_snapshot.dart';
import '../../core/router/app_router.dart';

class MonitoringScreen extends ConsumerStatefulWidget {
  const MonitoringScreen({super.key});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

// Telemetry helper class removed

class _MonitoringScreenState extends ConsumerState<MonitoringScreen> {
  String _selectedSeverity = 'HIGH'; // Default severity for simulation

  void _triggerCrash() {
    ref.read(vehiSafeServiceProvider).simulateCrash(_selectedSeverity);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Simulating $_selectedSeverity severity crash alert payload...'),
        backgroundColor: AppColors.severityHigh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(sensorTelemetryProvider);
    final settings = ref.watch(appSettingsProvider);
    final deviceStatusAsync = ref.watch(deviceStatusProvider);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final deviceConnected = deviceStatusAsync.valueOrNull?.isConnected ?? false;

    // Get active state string
    String systemStatus = 'Standby';
    Color statusColor = Colors.amber;
    if (deviceConnected) {
      systemStatus = 'Monitoring';
      statusColor = AppColors.statusConnected;
    }
    
    final activeAlert = ref.watch(activeAlertStateProvider);
    if (activeAlert != null) {
      systemStatus = 'Alert Active';
      statusColor = AppColors.severityHigh;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('REAL-TIME TELEMETRY'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.lightDivider),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'System Operational Status',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      systemStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // Live Telemetry Grid
            telemetryAsync.when(
              data: (snapshot) => _buildTelemetryGrid(snapshot, isDark),
              loading: () => _buildTelemetryGrid(
                SensorSnapshot(imuG: 1.0, pressureHpa: 1013.2, speedKmh: 0.0, gpsSignal: 0),
                isDark,
                isLoading: true,
              ),
              error: (err, stack) => _buildTelemetryGrid(
                SensorSnapshot(imuG: 0.0, pressureHpa: 0.0, speedKmh: 0.0, gpsSignal: 0),
                isDark,
                isError: true,
              ),
            ),

            const SizedBox(height: 24),

            // Developer Simulation Panel
            if (settings.developerMode)
              _buildSimulationPanel(isDark)
            else
              _buildSimulationPrompt(isDark),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryGrid(SensorSnapshot snapshot, bool isDark, {bool isLoading = false, bool isError = false}) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSensorCard(
                'IMU ACCELERATION',
                '${snapshot.imuG} G',
                Icons.speed,
                Colors.purple,
                'Normal Gravity ~1.0G',
                isDark,
                isLoading: isLoading,
                isError: isError,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSensorCard(
                'BAROMETRIC PRESSURE',
                '${snapshot.pressureHpa} hPa',
                Icons.compress,
                Colors.teal,
                'Standard Sea Level ~1013hPa',
                isDark,
                isLoading: isLoading,
                isError: isError,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSensorCard(
                'GPS SPEED',
                '${snapshot.speedKmh} km/h',
                Icons.directions_run,
                Colors.blue,
                'Current Speed',
                isDark,
                isLoading: isLoading,
                isError: isError,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSensorCard(
                'GPS SIGNAL',
                '${snapshot.gpsSignal}%',
                Icons.network_ping,
                Colors.orange,
                snapshot.gpsSignal > 80 ? 'Excellent' : 'Searching satellites...',
                isDark,
                isLoading: isLoading,
                isError: isError,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSensorCard(
    String title,
    String value,
    IconData icon,
    Color iconColor,
    String caption,
    bool isDark, {
    required bool isLoading,
    required bool isError,
  }) {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.lightDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else if (isError)
            const Text('N/A', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.grey))
          else
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
            ),
          const Spacer(),
          Text(
            caption,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationPanel(bool isDark) {
    Color selectedColor = AppColors.severityHigh;
    String details = '';
    if (_selectedSeverity == 'LOW') {
      selectedColor = AppColors.severityLow;
      details = '• 30-Second Countdown Timer\n• Dispatches coordinates to emergency contacts only\n• Allows Pin / Biometrics bypass';
    } else if (_selectedSeverity == 'MEDIUM') {
      selectedColor = AppColors.severityMedium;
      details = '• 15-Second Countdown Timer\n• Escalates dispatch to rescue services + contacts\n• Allows Pin / Biometrics bypass';
    } else {
      selectedColor = AppColors.severityHigh;
      details = '• 10-Second Urgent Countdown Timer\n• PIN-only cancellation (Biometrics completely disabled)\n• Auto-sends payload via LTE + SMS fallback channels';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: selectedColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selectedColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report, color: selectedColor),
              const SizedBox(width: 12),
              Text(
                'CRASH SIMULATION BOARD',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: selectedColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Test the emergency response system locally. Tap a severity below to review its alert configuration rules and trigger a simulation.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          const Text('Select Target Severity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            children: ['LOW', 'MEDIUM', 'HIGH'].map((sev) {
              final isSelected = _selectedSeverity == sev;
              Color btnColor = AppColors.severityLow;
              if (sev == 'MEDIUM') btnColor = AppColors.severityMedium;
              if (sev == 'HIGH') btnColor = AppColors.severityHigh;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Center(
                      child: Text(
                        sev,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : btnColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: btnColor,
                    backgroundColor: AppColors.darkSurface,
                    side: BorderSide(color: btnColor),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedSeverity = sev;
                        });
                      }
                    },
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Rule box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_selectedSeverity SEVERITY TRIGGER RULES:',
                  style: TextStyle(color: selectedColor, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  details,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _triggerCrash,
            icon: const Icon(Icons.emergency),
            label: const Text('TRIGGER CRASH SIMULATION', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: selectedColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationPrompt(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.lightDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.developer_mode, color: isDark ? Colors.white : Colors.black),
              const SizedBox(width: 12),
              const Text(
                'CRASH TEST SIMULATIONS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'To run mock crash telemetry triggers, enable Developer Mode first.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              ref.read(routerProvider).go('/settings');
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(45),
            ),
            child: const Text('Go to Settings'),
          )
        ],
      ),
    );
  }
}
