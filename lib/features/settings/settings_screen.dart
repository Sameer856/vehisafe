import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/models/vehicle_config.dart';
import '../../core/models/emergency_contact.dart';
import '../../core/widgets/custom_pin_pad.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // --- Contact Editing Fields ---
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // --- Notification Toggles (Mock) ---
  bool _smsEnabled = true;
  bool _pushEnabled = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // --- Contact Actions ---
  void _showAddEditContactDialog([EmergencyContact? contact]) {
    final isEditing = contact != null;
    if (isEditing) {
      _nameController.text = contact.name;
      _phoneController.text = contact.phoneNumber;
    } else {
      _nameController.clear();
      _phoneController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text(isEditing ? 'Edit Contact' : 'Add Contact', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                labelStyle: TextStyle(color: AppColors.darkTextSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.darkDivider)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                labelStyle: TextStyle(color: AppColors.darkTextSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.darkDivider)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.darkTextSecondary)),
          ),
          TextButton(
            onPressed: () {
              final name = _nameController.text.trim();
              final phone = _phoneController.text.trim();
              if (name.isEmpty || phone.isEmpty) return;

              final contactsNotifier = ref.read(emergencyContactsProvider.notifier);
              if (isEditing) {
                contactsNotifier.updateContact(
                  contact.copyWith(name: name, phoneNumber: phone),
                );
              } else {
                contactsNotifier.addContact(name, phone);
              }
              Navigator.of(context).pop();
              _syncConfigurationToPi();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isEditing ? 'Contact updated.' : 'Contact added.'),
                  backgroundColor: AppColors.brandPrimary,
                ),
              );
            },
            child: Text(isEditing ? 'Save' : 'Add', style: const TextStyle(color: AppColors.brandPrimary)),
          ),
        ],
      ),
    );
  }

  void _deleteContact(String id) {
    ref.read(emergencyContactsProvider.notifier).deleteContact(id);
    _syncConfigurationToPi();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact deleted.')),
    );
  }

  Future<void> _syncConfigurationToPi() async {
    try {
      final contacts = ref.read(emergencyContactsProvider);
      final vehicleConfig = ref.read(vehicleConfigProvider) ?? VehicleConfig(type: 'Car', year: DateTime.now().year);
      final settings = ref.read(appSettingsProvider);
      
      await ref.read(vehiSafeServiceProvider).uploadConfiguration(
        contacts: contacts,
        vehicleConfig: vehicleConfig,
        pin: '',
        biometricEnabled: settings.biometricEnabled,
        customMessage: settings.customMessage,
        onProgress: (_) {},
      );
      debugPrint('[SETTINGS SCREEN] Sync to Pi successful.');
    } catch (e) {
      debugPrint('[SETTINGS SCREEN] Sync to Pi skipped/failed: $e');
    }
  }

  // --- Vehicle Config Changer ---
  void _showVehicleConfigDialog() {
    final currentConfig = ref.read(vehicleConfigProvider);
    String selectedType = currentConfig?.type ?? 'Car';
    int selectedYear = currentConfig?.year ?? DateTime.now().year;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: const Text('Vehicle Details', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vehicle Type:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedType,
                dropdownColor: AppColors.darkSurface,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.darkDivider)),
                ),
                items: ['Car', 'SUV', 'Truck', 'Two-Wheeler']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedType = val);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Model Year:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () {
                      if (selectedYear > 1990) {
                        setDialogState(() => selectedYear--);
                      }
                    },
                    icon: const Icon(Icons.remove, color: Colors.white),
                  ),
                  Text('$selectedYear', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(
                    onPressed: () {
                      if (selectedYear < DateTime.now().year + 1) {
                        setDialogState(() => selectedYear++);
                      }
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.darkTextSecondary)),
            ),
            TextButton(
              onPressed: () {
                ref.read(vehicleConfigProvider.notifier).saveConfig(
                      VehicleConfig(type: selectedType, year: selectedYear),
                    );
                Navigator.of(context).pop();
                _syncConfigurationToPi();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vehicle configuration saved.')),
                );
              },
              child: const Text('Save', style: TextStyle(color: AppColors.brandPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // --- PIN Reset Manager ---
  void _showChangePinDialog() {
    String currentPin = '';
    String newPin = '';
    String confirmPin = '';
    int step = 1; // 1: Enter Current, 2: Enter New, 3: Confirm New
    String? pinError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void handleKey(String key) {
            setDialogState(() {
              pinError = null;
              if (step == 1) {
                if (currentPin.length < 4) {
                  currentPin += key;
                  if (currentPin.length == 4) {
                    final settingsNotifier = ref.read(appSettingsProvider.notifier);
                    if (settingsNotifier.verifyPin(currentPin)) {
                      step = 2;
                    } else {
                      currentPin = '';
                      pinError = 'Incorrect current PIN.';
                    }
                  }
                }
              } else if (step == 2) {
                if (newPin.length < 4) {
                  newPin += key;
                  if (newPin.length == 4) {
                    step = 3;
                  }
                }
              } else if (step == 3) {
                if (confirmPin.length < 4) {
                  confirmPin += key;
                  if (confirmPin.length == 4) {
                    if (newPin == confirmPin) {
                      ref.read(appSettingsProvider.notifier).updateSettings(pin: newPin);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PIN updated successfully.')),
                      );
                    } else {
                      confirmPin = '';
                      newPin = '';
                      step = 2;
                      pinError = 'PINs do not match. Re-enter new PIN.';
                    }
                  }
                }
              }
            });
          }

          void handleDelete() {
            setDialogState(() {
              if (step == 1 && currentPin.isNotEmpty) {
                currentPin = currentPin.substring(0, currentPin.length - 1);
              } else if (step == 2 && newPin.isNotEmpty) {
                newPin = newPin.substring(0, newPin.length - 1);
              } else if (step == 3 && confirmPin.isNotEmpty) {
                confirmPin = confirmPin.substring(0, confirmPin.length - 1);
              }
            });
          }

          String title = 'Verify Current PIN';
          String subtitle = 'Enter your current 4-digit PIN code.';
          String dots = currentPin;
          if (step == 2) {
            title = 'Enter New PIN';
            subtitle = 'Enter a new 4-digit PIN code.';
            dots = newPin;
          } else if (step == 3) {
            title = 'Confirm New PIN';
            subtitle = 'Confirm the new 4-digit PIN code.';
            dots = confirmPin;
          }

          return AlertDialog(
            backgroundColor: AppColors.darkSurface,
            title: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (pinError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(pinError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final active = dots.length > index;
                    return Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? AppColors.brandPrimary : Colors.transparent,
                        border: Border.all(
                          color: active ? AppColors.brandPrimary : AppColors.darkDivider,
                          width: 1.5,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                CustomPinPad(
                  onKeyPressed: handleKey,
                  onDeletePressed: handleDelete,
                  showBiometric: false,
                )
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Transfer Device Wizard ---
  void _showTransferDeviceWizard() {
    String currentPin = '';
    String? pinError;
    int step = 1; // 1: Verify PIN, 2: Vehicle selection, 3: Completed
    String selectedType = 'Car';
    int selectedYear = DateTime.now().year;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setWizardState) {
          void handleKey(String key) {
            setWizardState(() {
              pinError = null;
              if (currentPin.length < 4) {
                currentPin += key;
                if (currentPin.length == 4) {
                  final settingsNotifier = ref.read(appSettingsProvider.notifier);
                  if (settingsNotifier.verifyPin(currentPin)) {
                    step = 2;
                  } else {
                    currentPin = '';
                    pinError = 'Incorrect security PIN.';
                  }
                }
              }
            });
          }

          void handleDelete() {
            setWizardState(() {
              if (currentPin.isNotEmpty) {
                currentPin = currentPin.substring(0, currentPin.length - 1);
              }
            });
          }

          if (step == 1) {
            return AlertDialog(
              backgroundColor: AppColors.darkSurface,
              title: const Text('Transfer Device - Step 1', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter your security PIN to confirm ownership authorization.',
                      style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  if (pinError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(pinError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final active = currentPin.length > index;
                      return Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? AppColors.brandPrimary : Colors.transparent,
                          border: Border.all(
                            color: active ? AppColors.brandPrimary : AppColors.darkDivider,
                            width: 1.5,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  CustomPinPad(
                    onKeyPressed: handleKey,
                    onDeletePressed: handleDelete,
                    showBiometric: false,
                  )
                ],
              ),
            );
          }

          if (step == 2) {
            return AlertDialog(
              backgroundColor: AppColors.darkSurface,
              title: const Text('Transfer Device - Step 2', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select the vehicle details of the target vehicle:',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  const Text('Vehicle Type:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    dropdownColor: AppColors.darkSurface,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.darkDivider)),
                    ),
                    value: selectedType,
                    items: ['Car', 'SUV', 'Truck', 'Two-Wheeler']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setWizardState(() => selectedType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Model Year:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          if (selectedYear > 1990) {
                            setWizardState(() => selectedYear--);
                          }
                        },
                        icon: const Icon(Icons.remove, color: Colors.white),
                      ),
                      Text('$selectedYear', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(
                        onPressed: () {
                          if (selectedYear < DateTime.now().year + 1) {
                            setWizardState(() => selectedYear++);
                          }
                        },
                        icon: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.darkTextSecondary)),
                ),
                TextButton(
                  onPressed: () {
                    // Update vehicle config
                    ref.read(vehicleConfigProvider.notifier).saveConfig(
                          VehicleConfig(type: selectedType, year: selectedYear),
                        );
                    // Reset calibration drives count back to 0
                    ref.read(appSettingsProvider.notifier).updateSettings(calibrationDrives: 0);
                    
                    setWizardState(() {
                      step = 3;
                    });
                  },
                  child: const Text('Transfer', style: TextStyle(color: AppColors.brandPrimary)),
                ),
              ],
            );
          }

          // Step 3
          return AlertDialog(
            backgroundColor: AppColors.darkSurface,
            title: const Text('Device Transferred!', style: TextStyle(color: Colors.white)),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 64),
                SizedBox(height: 16),
                Text(
                  'VehiSafe Raspberry Pi configuration updated. Please complete 2 calibration drives in your new vehicle to re-train sensor collision profiles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done', style: TextStyle(color: AppColors.brandPrimary)),
              )
            ],
          );
        },
      ),
    );
  }

  // --- Device Hotspot Configuration Mode Trigger ---
  void _enterConfigurationMode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Enter Configuration Mode?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This puts the Raspberry Pi device into local configuration AP mode. Cellular telemetry sync will suspend, and you will need to re-pair via local WiFi to upload parameters.',
          style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.darkTextSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Reset device service pairing states
              await ref.read(vehiSafeServiceProvider).resetDevice();
              // Mark settings not onboarded to activate router redirect
              await ref.read(appSettingsProvider.notifier).updateSettings(isOnboarded: false);
              // Router redirect handles the swap
              if (context.mounted) {
                context.go('/onboarding');
              }
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  void _showCustomMessageDialog() {
    final settings = ref.read(appSettingsProvider);
    final controller = TextEditingController(text: settings.customMessage);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Custom SMS Template', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure the custom message text prefix to be sent inside the emergency SMS alerts.',
              style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enter alert message prefix...',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.darkDivider)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.brandPrimary)),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: GPS coordinates, maps link, speed, and video links will automatically append to the end of the final SMS.',
              style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.darkTextSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              await ref.read(appSettingsProvider.notifier).updateSettings(customMessage: text);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              
              _syncConfigurationToPi();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Custom alert message updated and syncing to Pi...'),
                  backgroundColor: AppColors.brandPrimary,
                ),
              );
            },
            child: const Text('Save', style: TextStyle(color: AppColors.brandPrimary)),
          ),
        ],
      ),
    );
  }

  // --- Factory reset device ---
  void _showFactoryResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Factory Reset System?', style: TextStyle(color: Colors.red)),
        content: const Text(
          'This will permanently delete emergency contacts, PIN codes, calibration steps, and history logs from both the app and the Raspberry Pi unit. All pairings will wipe.',
          style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.darkTextSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              // Reset storage files completely
              final storage = ref.read(storageServiceProvider);
              await storage.resetAll();
              
              // Clear provider states
              await ref.read(appSettingsProvider.notifier).clearSettings();
              await ref.read(vehicleConfigProvider.notifier).clearConfig();
              await ref.read(emergencyContactsProvider.notifier).clearContacts();
              await ref.read(alertHistoryProvider.notifier).clearHistory();

              // Reset hardware simulation state
              await ref.read(vehiSafeServiceProvider).resetDevice();

              // Navigate back to onboarding
              if (context.mounted) {
                context.go('/onboarding');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('VehiSafe system factory reset completed.')),
                );
              }
            },
            child: const Text('Reset All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final vehicle = ref.watch(vehicleConfigProvider);
    final contacts = ref.watch(emergencyContactsProvider);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('SETTINGS PANEL', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section: Emergency Contacts
          _buildSectionHeader('Emergency Contacts (${contacts.length}/3)'),
          ...contacts.map((contact) => Card(
                color: AppColors.darkSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.darkDivider),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: Text(contact.phoneNumber, style: const TextStyle(color: AppColors.darkTextSecondary)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                        onPressed: () => _showAddEditContactDialog(contact),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteContact(contact.id),
                      ),
                    ],
                  ),
                ),
              )),
          if (contacts.length < 3)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: OutlinedButton.icon(
                onPressed: () => _showAddEditContactDialog(),
                icon: const Icon(Icons.add, color: AppColors.brandPrimary),
                label: const Text('Add Emergency Contact', style: TextStyle(color: AppColors.brandPrimary)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: AppColors.brandPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Section: Vehicle Settings
          _buildSectionHeader('Vehicle & Device Settings'),
          Card(
            color: AppColors.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.darkDivider),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.directions_car, color: AppColors.brandPrimary),
                  title: const Text('Vehicle Details', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: Text(vehicle != null ? '${vehicle.type} | Model Year: ${vehicle.year}' : 'Not configured', style: const TextStyle(color: AppColors.darkTextSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: _showVehicleConfigDialog,
                ),
                const Divider(color: AppColors.darkDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_horiz, color: Colors.amber),
                  title: const Text('Transfer Device to Another Vehicle', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Migrate hardware profile securely', style: TextStyle(color: AppColors.darkTextSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: _showTransferDeviceWizard,
                ),
                const Divider(color: AppColors.darkDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.wifi_tethering, color: Colors.amber),
                  title: const Text('Device Reconfiguration', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Re-enter setup AP and configuration upload', style: TextStyle(color: AppColors.darkTextSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: _enterConfigurationMode,
                ),
                const Divider(color: AppColors.darkDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_input_antenna, color: Colors.blue),
                  title: const Text('Enter Configuration Mode', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Suspend cell sync & pair local WiFi network', style: TextStyle(color: AppColors.darkTextSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: _enterConfigurationMode,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section: Security
          _buildSectionHeader('Security & Preferences'),
          Card(
            color: AppColors.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.darkDivider),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline, color: Colors.green),
                  title: const Text('Change Security PIN', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Re-authenticate and reset 4-digit code', style: TextStyle(color: AppColors.darkTextSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: _showChangePinDialog,
                ),
                const Divider(color: AppColors.darkDivider, height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint, color: Colors.teal),
                  title: const Text('Biometric Authentication', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Use fingerprint for fast cancel triggers', style: TextStyle(color: AppColors.darkTextSecondary)),
                  value: settings.biometricEnabled,
                  activeColor: AppColors.brandPrimary,
                  onChanged: (val) {
                    ref.read(appSettingsProvider.notifier).updateSettings(biometricEnabled: val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section: Notifications (Mock)
          _buildSectionHeader('Alert Preferences'),
          Card(
            color: AppColors.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.darkDivider),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.message_outlined, color: Colors.blue),
                  title: const Text('SMS Contact Alerts', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Send SMS links with GPS coordinates', style: TextStyle(color: AppColors.darkTextSecondary)),
                  value: _smsEnabled,
                  activeColor: AppColors.brandPrimary,
                  onChanged: (val) => setState(() => _smsEnabled = val),
                ),
                const Divider(color: AppColors.darkDivider, height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined, color: Colors.purple),
                  title: const Text('Critical Push Banners', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Receive heads-up status alerts', style: TextStyle(color: AppColors.darkTextSecondary)),
                  value: _pushEnabled,
                  activeColor: AppColors.brandPrimary,
                  onChanged: (val) => setState(() => _pushEnabled = val),
                ),
                const Divider(color: AppColors.darkDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_note, color: Colors.teal),
                  title: const Text('Custom Alert Message', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: Text(
                    settings.customMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: _showCustomMessageDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section: Developer Tools
          _buildSectionHeader('Developer Settings'),
          Card(
            color: AppColors.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.darkDivider),
            ),
            child: SwitchListTile(
              secondary: const Icon(Icons.developer_mode, color: Colors.grey),
              title: const Text('Developer Mode', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              subtitle: const Text('Enables mock crash simulation dashboards', style: TextStyle(color: AppColors.darkTextSecondary)),
              value: settings.developerMode,
              activeColor: AppColors.brandPrimary,
              onChanged: (val) {
                ref.read(appSettingsProvider.notifier).updateSettings(developerMode: val);
                if (val) {
                  // Instantly trigger high severity crash simulation
                  ref.read(vehiSafeServiceProvider).simulateCrash('HIGH');
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(val ? 'Developer Mode Enabled: Triggering HIGH alert simulation...' : 'Developer Mode Disabled.'),
                    backgroundColor: val ? AppColors.severityHigh : AppColors.brandPrimary,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Section: Danger Zone Reset
          _buildSectionHeader('Danger Zone'),
          Card(
            color: AppColors.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.redAccent, width: 1),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Device Reset / Factory Reset', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
              subtitle: const Text('Wipes pairing, PIN codes, contacts, logs and storage', style: TextStyle(color: AppColors.darkTextSecondary)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
              onTap: _showFactoryResetDialog,
            ),
          ),

          const SizedBox(height: 40),

          // App build information
          Center(
            child: Column(
              children: [
                Text(
                  'VehiSafe Mobile Control Panel',
                  style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Version 1.0.0 (Build 24)',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                const SizedBox(height: 24),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          color: Colors.grey,
        ),
      ),
    );
  }
}
