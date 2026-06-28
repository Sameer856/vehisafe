import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/models/alert_event.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _selectedFilter = 'All'; // All, Sent, Cancelled, High Severity

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(alertHistoryProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Filter events
    final filteredEvents = history.where((event) {
      if (_selectedFilter == 'Sent') {
        return event.outcome == 'Sent';
      }
      if (_selectedFilter == 'Cancelled') {
        return event.outcome == 'Cancelled' || event.outcome == 'False Alarm';
      }
      if (_selectedFilter == 'High Severity') {
        return event.severityLevel == 'HIGH';
      }
      return true; // 'All'
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('ALERT LOG HISTORY', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              onPressed: _showClearHistoryDialog,
            )
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Sent', 'Cancelled', 'High Severity'].map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(
                        filter,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.grey,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.brandPrimary,
                      backgroundColor: AppColors.darkSurface,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedFilter = filter;
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const Divider(height: 1),

          // Events List
          Expanded(
            child: filteredEvents.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    itemCount: filteredEvents.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final event = filteredEvents[index];
                      return _buildEventItem(event, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off,
            size: 80,
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          ),
          const SizedBox(height: 16),
          Text(
            'No alert history found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilter == 'All'
                ? 'Crash detections will appear here automatically.'
                : 'No incidents match the "$_selectedFilter" filter.',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(AlertEvent event, bool isDark) {
    final dateStr = DateFormat('MMM dd, yyyy').format(event.timestamp);
    final timeStr = DateFormat('HH:mm:ss').format(event.timestamp);

    Color severityColor = AppColors.severityLow;
    if (event.severityLevel == 'MEDIUM') severityColor = AppColors.severityMedium;
    if (event.severityLevel == 'HIGH') severityColor = AppColors.severityHigh;

    Color outcomeColor = Colors.grey;
    if (event.outcome == 'Sent') outcomeColor = Colors.red;
    if (event.outcome == 'Cancelled') outcomeColor = Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 6,
          height: 40,
          decoration: BoxDecoration(
            color: severityColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${event.severityLevel} Alert',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: outcomeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                event.outcome.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: outcomeColor),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            '$dateStr at $timeStr | Lat: ${event.gpsLat.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                
                // Sensor Readouts title
                const Text(
                  'TELEMETRY SNAPSHOT AT IMPACT:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                
                // Sensor grid
                Row(
                  children: [
                    _buildSnapshotValue('IMU G-Force', '${event.sensorSnapshot.imuG} G', isDark),
                    const SizedBox(width: 8),
                    _buildSnapshotValue('Pressure', '${event.sensorSnapshot.pressureHpa} hPa', isDark),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSnapshotValue('Speed', '${event.sensorSnapshot.speedKmh} km/h', isDark),
                    const SizedBox(width: 8),
                    _buildSnapshotValue('GPS Signal', '${event.sensorSnapshot.gpsSignal}%', isDark),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Contacts notified list
                const Text(
                  'NOTIFIED EMERGENCY SERVICES / CONTACTS:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                if (event.contactsNotified.isEmpty)
                  const Text('No emergency contacts registered.', style: TextStyle(color: Colors.grey, fontSize: 13))
                else
                  ...event.contactsNotified.map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check, color: Colors.green, size: 16),
                                const SizedBox(width: 8),
                                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ],
                            ),
                            Text(c.phoneNumber, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      )),
                      
                const SizedBox(height: 20),
                
                // Incident timeline
                const Text(
                  'RESPONSE TIMELINE:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                _buildTimelineItem(event.timestamp, 'Telemetry collision threshold breached'),
                if (event.outcome == 'Sent') ...[
                  _buildTimelineItem(event.timestamp.add(const Duration(seconds: 1)), 'Satellite payload packaging completed'),
                  _buildTimelineItem(event.timestamp.add(const Duration(seconds: 3)), 'Dispatched SMS coordinates to contacts'),
                  _buildTimelineItem(event.timestamp.add(const Duration(seconds: 4)), 'GPS coordinates sent to emergency response center'),
                ] else ...[
                  _buildTimelineItem(event.timestamp.add(const Duration(seconds: 2)), 'Cancellation code entered via PIN/Biometric'),
                  _buildTimelineItem(event.timestamp.add(const Duration(seconds: 3)), 'Active dispatch cancelled successfully'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotValue(String label, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.lightDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(DateTime time, String detail) {
    final timeStr = DateFormat('HH:mm:ss').format(time);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeStr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Log History?'),
        content: const Text('This will permanently delete all logged crash alerts. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(alertHistoryProvider.notifier).clearHistory();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log history cleared.')),
              );
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
