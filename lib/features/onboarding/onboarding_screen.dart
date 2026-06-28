import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/models/vehicle_config.dart';
import '../../core/models/emergency_contact.dart';
import '../../core/widgets/custom_pin_pad.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();

  // Onboarding Data States
  String? _selectedVehicleType;
  int _selectedVehicleYear = DateTime.now().year;
  
  final List<EmergencyContact> _tempContacts = [];
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactPhoneController = TextEditingController();

  String _pinCode = '';
  String _confirmPinCode = '';
  bool _isConfirmingPin = false;
  String? _pinError;

  bool _biometricsSupported = false;
  bool _biometricsEnabled = false;

  // Pairing & Upload State
  bool _isScanning = false;
  List<String> _scannedDevices = [];
  String? _selectedDeviceName;
  bool _isUploadingConfig = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await ref.read(biometricServiceProvider).isBiometricAvailable();
    if (mounted) {
      setState(() {
        _biometricsSupported = available;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // --- Step Handlers ---
  void _selectVehicleType(String type) {
    setState(() {
      _selectedVehicleType = type;
    });
    _nextPage();
  }

  void _saveVehicleInfo() {
    if (_selectedVehicleType == null) return;
    ref.read(vehicleConfigProvider.notifier).saveConfig(
      VehicleConfig(type: _selectedVehicleType!, year: _selectedVehicleYear),
    );
    _nextPage();
  }

  void _addContact() {
    final name = _contactNameController.text.trim();
    final phone = _contactPhoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) return;

    setState(() {
      _tempContacts.add(EmergencyContact(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        phoneNumber: phone,
      ));
      _contactNameController.clear();
      _contactPhoneController.clear();
    });
    Navigator.of(context).pop();
  }

  void _removeContact(String id) {
    setState(() {
      _tempContacts.removeWhere((c) => c.id == id);
    });
  }

  void _saveContacts() {
    if (_tempContacts.isEmpty) return;
    final contactsNotifier = ref.read(emergencyContactsProvider.notifier);
    contactsNotifier.clearContacts();
    for (var contact in _tempContacts) {
      contactsNotifier.addContact(contact.name, contact.phoneNumber);
    }
    _nextPage();
  }

  void _handlePinKey(String key) {
    setState(() {
      _pinError = null;
      if (!_isConfirmingPin) {
        if (_pinCode.length < 4) {
          _pinCode += key;
          if (_pinCode.length == 4) {
            Future.delayed(const Duration(milliseconds: 200), () {
              setState(() {
                _isConfirmingPin = true;
              });
            });
          }
        }
      } else {
        if (_confirmPinCode.length < 4) {
          _confirmPinCode += key;
          if (_confirmPinCode.length == 4) {
            if (_pinCode == _confirmPinCode) {
              ref.read(appSettingsProvider.notifier).updateSettings(pin: _pinCode);
              Future.delayed(const Duration(milliseconds: 200), () {
                _nextPage();
              });
            } else {
              Future.delayed(const Duration(milliseconds: 200), () {
                setState(() {
                  _confirmPinCode = '';
                  _pinCode = '';
                  _isConfirmingPin = false;
                  _pinError = 'PINs do not match. Please try again.';
                });
              });
            }
          }
        }
      }
    });
  }

  void _handlePinDelete() {
    setState(() {
      if (!_isConfirmingPin) {
        if (_pinCode.isNotEmpty) {
          _pinCode = _pinCode.substring(0, _pinCode.length - 1);
        }
      } else {
        if (_confirmPinCode.isNotEmpty) {
          _confirmPinCode = _confirmPinCode.substring(0, _confirmPinCode.length - 1);
        }
      }
    });
  }

  void _saveBiometricsChoice(bool enabled) {
    setState(() {
      _biometricsEnabled = enabled;
    });
    ref.read(appSettingsProvider.notifier).updateSettings(biometricEnabled: enabled);
    _nextPage();
  }

  // --- Pairing & Configuration Upload Simulations ---

  void _startDeviceScanning() async {
    setState(() {
      _isScanning = true;
      _scannedDevices = [];
      _selectedDeviceName = null;
      _isUploadingConfig = false;
    });

    final devices = await ref.read(vehiSafeServiceProvider).scanForDevices();
    
    if (mounted) {
      setState(() {
        _isScanning = false;
        _scannedDevices = devices;
      });
    }
  }

  void _connectToSelectedDevice(String deviceName) async {
    setState(() {
      _isScanning = false;
      _selectedDeviceName = deviceName;
    });

    await ref.read(vehiSafeServiceProvider).connectToDevice(deviceName);

    if (mounted) {
      // Start upload automatically
      _startConfigurationUpload();
    }
  }

  void _startConfigurationUpload() async {
    setState(() {
      _isUploadingConfig = true;
      _uploadProgress = 0.0;
    });

    final contacts = _tempContacts;
    final vehicleConfig = VehicleConfig(type: _selectedVehicleType ?? 'Car', year: _selectedVehicleYear);

    try {
      await ref.read(vehiSafeServiceProvider).uploadConfiguration(
        contacts: contacts,
        vehicleConfig: vehicleConfig,
        pin: _pinCode,
        biometricEnabled: _biometricsEnabled,
        customMessage: ref.read(appSettingsProvider).customMessage,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isUploadingConfig = false;
        });
        _nextPage();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingConfig = false;
        });
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.darkSurface,
            title: const Text('Connection Failure', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Could not reach the VehiSafe device at 192.168.4.1.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Troubleshooting Steps:',
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Open your phone\'s System WiFi Settings.\n'
                  '2. Verify you are connected to the "VehiSafe_Setup" hotspot.\n'
                  '3. Turn off cellular mobile data temporarily (sometimes the OS redirects local requests to LTE).\n'
                  '4. Close this dialog and click the device name to try again.',
                  style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13, height: 1.45),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Dismiss', style: TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }
  }

  void _completeOnboarding() {
    ref.read(appSettingsProvider.notifier).updateSettings(isOnboarded: true);
    
    // Initialize mock history
    final historyNotifier = ref.read(alertHistoryProvider.notifier);
    final vehiSafeService = ref.read(vehiSafeServiceProvider);
    vehiSafeService.getPrepopulatedHistory().then((mockHistory) {
      historyNotifier.populateMockHistory(mockHistory);
    });

    // Make sure device exits configuration mode
    ref.read(vehiSafeServiceProvider).setDeviceMode('Monitoring');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildWelcomePage(),
            _buildVehicleTypePage(),
            _buildVehicleYearPage(),
            _buildContactsPage(),
            _buildPinPage(),
            _buildBiometricPage(),
            _buildPairingPage(),
            _buildUploadSuccessPage(),
          ],
        ),
      ),
    );
  }

  // ==================== PAGE BUILDERS ====================

  // 1. Welcome Page
  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 100,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'VEHISAFE',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Raspberry Pi + Lapcare Modem Safety System',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.darkTextSecondary,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Get Started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 2. Vehicle Type Selection Page
  Widget _buildVehicleTypePage() {
    final vehicleTypes = [
      {'name': 'Car', 'icon': Icons.directions_car},
      {'name': 'SUV', 'icon': Icons.airport_shuttle},
      {'name': 'Truck', 'icon': Icons.local_shipping},
      {'name': 'Two-Wheeler', 'icon': Icons.two_wheeler},
    ];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(onPressed: _prevPage, icon: const Icon(Icons.arrow_back, color: Colors.white)),
          const SizedBox(height: 20),
          const Text(
            'Select Vehicle Type',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            'This optimizes sensor thresholds. Selecting Two-Wheeler disables barometric pressure crash checks.',
            style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: vehicleTypes.length,
              itemBuilder: (context, index) {
                final type = vehicleTypes[index];
                final name = type['name'] as String;
                final icon = type['icon'] as IconData;
                final isSelected = _selectedVehicleType == name;

                return GestureDetector(
                  onTap: () => _selectVehicleType(name),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.brandPrimary.withValues(alpha: 0.15) : AppColors.darkSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppColors.brandPrimary : AppColors.darkDivider,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 48, color: isSelected ? AppColors.brandPrimary : Colors.white),
                        const SizedBox(height: 12),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppColors.brandPrimary : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 3. Vehicle Year Selection Page
  Widget _buildVehicleYearPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(onPressed: _prevPage, icon: const Icon(Icons.arrow_back, color: Colors.white)),
          const SizedBox(height: 20),
          const Text(
            'Model Year',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            'Vehicle year helps us determine the appropriate connection adapter port (12V accessory socket or USB-C).',
            style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                Text(
                  '$_selectedVehicleYear',
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: AppColors.brandPrimary),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedVehicleYear > 1990) _selectedVehicleYear--;
                        });
                      },
                      icon: const Icon(Icons.remove_circle_outline, size: 48, color: Colors.white),
                    ),
                    const SizedBox(width: 40),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedVehicleYear < DateTime.now().year + 1) _selectedVehicleYear++;
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline, size: 48, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.darkDivider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.power_outlined, color: AppColors.brandPrimary),
                      const SizedBox(width: 12),
                      Text(
                        'Estimated Adapter: ${_selectedVehicleYear < 2020 ? '12V Accessory Plug' : 'USB-C Direct'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _saveVehicleInfo,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 4. Emergency Contacts Setup Page
  Widget _buildContactsPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(onPressed: _prevPage, icon: const Icon(Icons.arrow_back, color: Colors.white)),
          const SizedBox(height: 20),
          const Text(
            'Emergency Contacts',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            'Add 1 to 3 contacts who will receive emergency coordinates text dispatches in case of an accident.',
            style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
          ),
          const SizedBox(height: 20),
          if (_tempContacts.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.contact_phone_outlined, size: 64, color: AppColors.brandPrimary.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    const Text('No contacts added yet', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    const Text('You must add at least 1 contact to proceed', style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _tempContacts.length,
                itemBuilder: (context, index) {
                  final contact = _tempContacts[index];
                  return Card(
                    color: AppColors.darkSurface,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.brandPrimary,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text(contact.phoneNumber, style: const TextStyle(color: AppColors.darkTextSecondary)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.severityHigh),
                        onPressed: () => _removeContact(contact.id),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_tempContacts.length < 3)
            OutlinedButton.icon(
              onPressed: _showAddContactDialog,
              icon: const Icon(Icons.add, color: AppColors.brandPrimary),
              label: const Text('Add Emergency Contact', style: TextStyle(color: AppColors.brandPrimary)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.brandPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _tempContacts.isNotEmpty ? _saveContacts : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showAddContactDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Add Contact', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _contactNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                labelStyle: TextStyle(color: AppColors.darkTextSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.darkDivider)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactPhoneController,
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
            onPressed: _addContact,
            child: const Text('Add', style: TextStyle(color: AppColors.brandPrimary)),
          ),
        ],
      ),
    );
  }

  // 5. PIN Setup Page
  Widget _buildPinPage() {
    final currentPinText = _isConfirmingPin ? _confirmPinCode : _pinCode;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  if (_isConfirmingPin) {
                    setState(() {
                      _isConfirmingPin = false;
                      _confirmPinCode = '';
                    });
                  } else {
                    _prevPage();
                  }
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isConfirmingPin ? 'Confirm Security PIN' : 'Create Security PIN',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            _isConfirmingPin
                ? 'Enter the 4-digit PIN code again to confirm.'
                : 'This PIN is used to cancel accidental crash dispatches.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
          ),
          const Spacer(),
          if (_pinError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                _pinError!,
                style: const TextStyle(color: AppColors.severityHigh, fontWeight: FontWeight.bold),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final active = currentPinText.length > index;
              return Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.brandPrimary : Colors.transparent,
                  border: Border.all(
                    color: active ? AppColors.brandPrimary : AppColors.darkDivider,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          const Spacer(),
          CustomPinPad(
            onKeyPressed: _handlePinKey,
            onDeletePressed: _handlePinDelete,
            showBiometric: false,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 6. Biometrics Prompt Page
  Widget _buildBiometricPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: _prevPage, icon: const Icon(Icons.arrow_back, color: Colors.white)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.fingerprint, size: 100, color: AppColors.brandPrimary),
          const SizedBox(height: 32),
          const Text(
            'Enable Biometric Auth',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Use your fingerprint or face recognition for quick alert cancellations during emergency countdowns.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
          ),
          const Spacer(),
          if (_biometricsSupported) ...[
            ElevatedButton(
              onPressed: () => _saveBiometricsChoice(true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Enable Biometric Authentication'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _saveBiometricsChoice(false),
              child: const Text('Skip for Now', style: TextStyle(color: AppColors.darkTextSecondary)),
            ),
          ] else ...[
            const Text(
              'Biometrics not supported or setup on this device.',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () => _saveBiometricsChoice(false),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue'),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 7. Pairing Page (Local WiFi Scanner)
  Widget _buildPairingPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: _prevPage, icon: const Icon(Icons.arrow_back, color: Colors.white)),
            ],
          ),
          const Spacer(),
          if (!_isScanning && _scannedDevices.isEmpty && !_isUploadingConfig) ...[
            Icon(Icons.wifi_find_outlined, size: 100, color: AppColors.brandPrimary.withValues(alpha: 0.6)),
            const SizedBox(height: 32),
            const Text('Local WiFi Pairing', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            const Text(
              'Connect directly to the VehiSafe hotspot local WiFi network to upload configuration variables. Internet connection is not required.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _startDeviceScanning,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Search for VehiSafe Devices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ] else if (_isScanning) ...[
            const RadarScanner(),
            const SizedBox(height: 48),
            const Text(
              'Scanning Local WiFi Band...',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text(
              'Listening for Raspberry Pi / Lapcare Wi-Fi signals',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.darkTextSecondary),
            ),
            const Spacer(),
          ] else if (_scannedDevices.isNotEmpty && !_isUploadingConfig) ...[
            const Icon(Icons.devices_other, size: 64, color: AppColors.brandPrimary),
            const SizedBox(height: 16),
            const Text('VehiSafe Devices Found', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Select your hardware device hotspot to configure:', style: TextStyle(color: AppColors.darkTextSecondary)),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _scannedDevices.length,
                itemBuilder: (context, index) {
                  final dev = _scannedDevices[index];
                  return Card(
                    color: AppColors.darkSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.brandPrimary, width: 1),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.wifi, color: AppColors.brandPrimary),
                      title: Text(dev, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: const Text('Local WiFi hotspot active', style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
                      onTap: () => _connectToSelectedDevice(dev),
                    ),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: _startDeviceScanning,
              child: const Text('Scan Again', style: TextStyle(color: AppColors.brandPrimary)),
            ),
          ] else if (_isUploadingConfig) ...[
            const SizedBox(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                strokeWidth: 6,
                valueColor: AlwaysStoppedAnimation(AppColors.brandPrimary),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'Uploading Configuration: ${(_uploadProgress * 100).toInt()}%',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48.0),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: AppColors.darkDivider,
                valueColor: const AlwaysStoppedAnimation(AppColors.brandPrimary),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Packaging emergency contacts, vehicle year thresholds, PIN signature, and local WiFi network credentials...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
            ),
            const Spacer(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 8. Upload Success Screen
  Widget _buildUploadSuccessPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: AppColors.statusConnected, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 32),
          const Text('Configuration Uploaded!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 12),
          const Text(
            'Vehicle parameters and contact rosters have been saved locally to the Raspberry Pi hardware device. Switching device to working mode.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
          ),
          const SizedBox(height: 32),
          
          // Setup Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('UPLOADED SCHEMA SUMMARY:', style: TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.bold, fontSize: 11)),
                const SizedBox(height: 12),
                _buildSummaryRow('Device Paired', _selectedDeviceName ?? 'VehiSafe-Pi-System'),
                const Divider(color: AppColors.darkDivider),
                _buildSummaryRow('Vehicle Details', '$_selectedVehicleType ($_selectedVehicleYear)'),
                const Divider(color: AppColors.darkDivider),
                _buildSummaryRow('Emergency Contacts', '${_tempContacts.length} upload(s)'),
                const Divider(color: AppColors.darkDivider),
                _buildSummaryRow('Biometric Bypass', _biometricsEnabled ? 'Enabled' : 'Disabled'),
              ],
            ),
          ),
          
          const Spacer(),
          ElevatedButton(
            onPressed: () {
              _completeOnboarding();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Finish Setup & Enter Panel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

// Radar Scanner Custom Widget for Premium Scanning Aesthetic
class RadarScanner extends StatefulWidget {
  const RadarScanner({super.key});

  @override
  State<RadarScanner> createState() => _RadarScannerState();
}

class _RadarScannerState extends State<RadarScanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse circles
            ...List.generate(3, (index) {
              final delay = index * 0.33;
              double progress = _controller.value - delay;
              if (progress < 0) progress += 1.0;
              return Container(
                width: 100 + (progress * 150),
                height: 100 + (progress * 150),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.brandPrimary.withValues(alpha: 1.0 - progress),
                    width: 2,
                  ),
                ),
              );
            }),
            // Central pulsing core
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandPrimary.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.brandPrimary, width: 2),
              ),
              child: const Icon(Icons.wifi_tethering, size: 40, color: AppColors.brandPrimary),
            ),
          ],
        );
      },
    );
  }
}
