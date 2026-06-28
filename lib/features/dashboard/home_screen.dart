import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/models/device_status.dart';
import '../../core/router/app_router.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isBannerDismissed = false;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    // Ticker to refresh relative sync timestamps every second
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  void _simulateDrive() {
    final settings = ref.read(appSettingsProvider);
    final currentDrives = settings.calibrationDrives;
    if (currentDrives < 2) {
      ref.read(appSettingsProvider.notifier).updateSettings(
        calibrationDrives: currentDrives + 1,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Drive ${currentDrives + 1}/2 recorded. Calibration updated.'),
          backgroundColor: AppColors.brandPrimary,
        ),
      );
    }
  }

  String _getRelativeTime(DateTime? timestamp) {
    if (timestamp == null) return 'Never';
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return DateFormat('HH:mm:ss').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final vehicle = ref.watch(vehicleConfigProvider);
    
    // Listen to device status stream
    final deviceStatusAsync = ref.watch(deviceStatusProvider);
    
    // Watch alert history for counting stats
    final history = ref.watch(alertHistoryProvider);
    final totalTriggered = history.length;
    final falseAlerts = history.where((e) => e.outcome == 'Cancelled' || e.outcome == 'False Alarm').length;

    final showCalibrationBanner = !settings.developerMode && 
        settings.calibrationDrives < 2 && 
        !_isBannerDismissed;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text(
          'VEHISAFE CONTROL PANEL',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              // Trigger a quick status flash or refresh
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Checking hardware telemetry sync status...'),
                  duration: Duration(milliseconds: 700),
                ),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vehicle config display
            if (vehicle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.darkDivider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            vehicle.type == 'Two-Wheeler' ? Icons.two_wheeler : Icons.directions_car,
                            color: AppColors.brandPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Vehicle: ${vehicle.type} (${vehicle.year})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Port: ${vehicle.chargingPort}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.brandPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),

            // Calibration Banner
            if (showCalibrationBanner)
              Card(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.amber, width: 1),
                ),
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Calibration Required',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.amber, size: 20),
                            onPressed: () {
                              setState(() {
                                _isBannerDismissed = true;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Perform 2 safe drives to calibrate collision sensors for your ${vehicle?.type ?? 'vehicle'}. Treads completed: ${settings.calibrationDrives}/2.',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _simulateDrive,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(120, 36),
                        ),
                        child: const Text('Record Drive Checkpoint', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),

            // Device Status Section
            deviceStatusAsync.when(
              data: (status) => _buildStatusWidgets(status),
              loading: () => _buildDeviceLoadingCard(),
              error: (err, stack) => _buildDeviceErrorCard(),
            ),

            const SizedBox(height: 20),

            // Quick Stats Card
            _buildStatsAndGPSLayout(deviceStatusAsync.valueOrNull, totalTriggered, falseAlerts),
            
            const SizedBox(height: 20),
            
            // App Quick Controls
            _buildQuickControlsCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- Widget Builders ---

  Widget _buildStatusWidgets(DeviceStatus status) {
    Color systemStatusColor = AppColors.statusConnected;
    if (status.currentMode == 'Configuration') {
      systemStatusColor = Colors.amber;
    } else if (status.currentMode == 'Alert') {
      systemStatusColor = AppColors.severityHigh;
    } else if (status.currentMode == 'Boot') {
      systemStatusColor = Colors.blue;
    }

    return Column(
      children: [
        // Main Header Hardware Dashboard
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkDivider),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.memory, color: Colors.blue, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        status.deviceName,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                  _buildGlowBadge(status.currentMode.toUpperCase(), systemStatusColor),
                ],
              ),
              const Divider(color: AppColors.darkDivider, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Firmware Version', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  Text(status.firmwareVersion, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Hardware Model', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const Text('Raspberry Pi & 4G USB Modem', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Grid of Network, GPS & Battery
        Row(
          children: [
            Expanded(
              child: _buildIndicatorCard(
                'CELL LTE SIGNAL',
                status.networkStatus,
                status.networkStatus == 'LTE Connected'
                    ? Icons.signal_cellular_4_bar
                    : (status.networkStatus == 'Searching...' ? Icons.network_ping : Icons.signal_cellular_off),
                status.networkStatus == 'LTE Connected'
                    ? Colors.green
                    : (status.networkStatus == 'Searching...' ? Colors.amber : Colors.red),
                status.networkStatus == 'LTE Connected' ? 'Cellular Active' : 'No LTE Service',
                status.networkStatus == 'Searching...',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildIndicatorCard(
                'GPS SAT SYSTEM',
                status.gpsStatus,
                status.gpsStatus == 'GPS Locked'
                    ? Icons.gps_fixed
                    : (status.gpsStatus == 'GPS Acquiring' ? Icons.gps_not_fixed : Icons.location_off),
                status.gpsStatus == 'GPS Locked'
                    ? Colors.green
                    : (status.gpsStatus == 'GPS Acquiring' ? Colors.amber : Colors.red),
                status.gpsStatus == 'GPS Locked' ? '${status.satellites} Satellites' : 'Locating Grid...',
                status.gpsStatus == 'GPS Acquiring',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildIndicatorCard(
                'DEVICE BATTERY',
                '${status.batteryPercent}%',
                status.batteryPercent > 50
                    ? Icons.battery_full
                    : (status.batteryPercent > 20 ? Icons.battery_charging_full : Icons.battery_alert),
                status.batteryPercent > 50
                    ? Colors.green
                    : (status.batteryPercent > 20 ? Colors.amber : Colors.red),
                'USB-C Connected',
                false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGlowBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
    bool showPulse,
  ) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              showPulse
                  ? _PulsingDot(color: color)
                  : Icon(icon, color: color, size: 16),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsAndGPSLayout(DeviceStatus? status, int total, int falseAlerts) {
    final hasLoc = status != null && status.latitude != null;
    final latStr = hasLoc ? status.latitude!.toStringAsFixed(5) : 'Searching...';
    final lngStr = hasLoc ? status.longitude!.toStringAsFixed(5) : 'Searching...';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GPS CARD
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.location_on_outlined, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'LAST KNOWN COORDS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Lat: $latStr', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Lng: $lngStr', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: hasLoc ? () {
                        Clipboard.setData(ClipboardData(text: '$latStr,$lngStr'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coordinates copied to clipboard')),
                        );
                      } : null,
                      child: const Row(
                        children: [
                          Icon(Icons.copy, size: 12, color: AppColors.brandPrimary),
                          SizedBox(width: 4),
                          Text('Copy', style: TextStyle(color: AppColors.brandPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Text(
                      _getRelativeTime(status?.lastSyncTime),
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // STATS CARD
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'CRASH ANALYTICS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Alerts Logged: $total',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cancelled: $falseAlerts',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'False Alarm Rate: ${total == 0 ? "0%" : "${((falseAlerts) / total * 100).toStringAsFixed(0)}%"}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceLoadingCard() {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.brandPrimary)),
            SizedBox(height: 12),
            Text('Syncing LTE/GPS telemetry...', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.severityHigh),
      ),
      child: const Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 40),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'VehiSafe cellular cloud sync failure. Check USB Modem LTE status.',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildQuickControlsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CONTROL SHORTCUTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.contact_phone_outlined, color: Colors.blue),
            ),
            title: const Text('Manage Emergency Contacts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () => ref.read(routerProvider).go('/settings'),
          ),
          const Divider(color: AppColors.darkDivider),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sensors, color: Colors.purple),
            ),
            title: const Text('Live Telemetry Dashboard', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () => ref.read(routerProvider).go('/monitoring'),
          ),
        ],
      ),
    );
  }
}

// Custom Pulsing Dot Widget for Active Mode Glows
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _pulseAnimation.value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 2,
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
