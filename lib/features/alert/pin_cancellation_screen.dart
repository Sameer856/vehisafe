import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/widgets/custom_pin_pad.dart';

class PinCancellationScreen extends ConsumerStatefulWidget {
  const PinCancellationScreen({super.key});

  @override
  ConsumerState<PinCancellationScreen> createState() => _PinCancellationScreenState();
}

class _PinCancellationScreenState extends ConsumerState<PinCancellationScreen> {
  String _enteredPin = '';
  int _attempts = 0;
  bool _isLockedOut = false;
  int _lockoutTimeRemaining = 0;
  Timer? _lockoutTimer;
  String? _errorMessage;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer() {
    setState(() {
      _isLockedOut = true;
      _lockoutTimeRemaining = 60;
      _errorMessage = 'Too many failed attempts. Locked for 60 seconds.';
    });

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      
      setState(() {
        if (_lockoutTimeRemaining <= 1) {
          _isLockedOut = false;
          _attempts = 0;
          _errorMessage = null;
          timer.cancel();
        } else {
          _lockoutTimeRemaining--;
          _errorMessage = 'Too many failed attempts. Locked for $_lockoutTimeRemaining seconds.';
        }
      });
    });
  }

  void _handlePinKey(String key) {
    if (_isLockedOut) return;

    setState(() {
      _errorMessage = null;
      if (_enteredPin.length < 4) {
        _enteredPin += key;
        
        if (_enteredPin.length == 4) {
          _verifyPin(_enteredPin);
        }
      }
    });
  }

  void _handlePinDelete() {
    if (_isLockedOut) return;
    
    setState(() {
      if (_enteredPin.isNotEmpty) {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      }
    });
  }

  void _verifyPin(String pin) {
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final isCorrect = settingsNotifier.verifyPin(pin);

    if (isCorrect) {
      // Cancel alert and log as false alarm
      ref.read(activeAlertStateProvider.notifier).cancelAlert('Cancelled');
      context.go('/home');
    } else {
      setState(() {
        _attempts++;
        _enteredPin = '';
        if (_attempts >= 3) {
          _startLockoutTimer();
        } else {
          _errorMessage = 'Incorrect PIN. Attempt $_attempts/3.';
        }
      });
    }
  }

  Future<void> _authenticateBiometrics() async {
    if (_isLockedOut) return;

    final biometricService = ref.read(biometricServiceProvider);
    final isAuthed = await biometricService.authenticate(
      'Authenticate to cancel emergency alert dispatch',
    );

    if (isAuthed && mounted) {
      // Cancel alert
      ref.read(activeAlertStateProvider.notifier).cancelAlert('Cancelled');
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final alertState = ref.watch(activeAlertStateProvider);
    
    // Redirect if alert state was cleared in the background (e.g. countdown expired)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (alertState == null) {
        context.go('/home');
      }
    });

    if (alertState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final showBiometric = settings.biometricEnabled && 
        alertState.severityLevel != 'HIGH' && 
        !_isLockedOut;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'CANCEL VERIFICATION',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 16, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            // Returns to countdown screen. Timer keeps running.
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const Icon(Icons.lock_outline, color: AppColors.brandPrimary, size: 48),
            const SizedBox(height: 16),
            const Text(
              'ENTER SECURITY PIN',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                _isLockedOut 
                    ? 'PIN entry locked' 
                    : (alertState.severityLevel == 'HIGH'
                        ? 'For HIGH severity impacts, biometric bypass is disabled. Enter your 4-digit PIN to authorize cancellation.'
                        : 'Enter your 4-digit PIN to cancel emergency services dispatch.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: alertState.severityLevel == 'HIGH' ? Colors.amber[700] : Colors.grey, 
                  fontSize: 13,
                  fontWeight: alertState.severityLevel == 'HIGH' ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            const Spacer(),
            
            // PIN Dots Indicator
            if (!_isLockedOut)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final active = _enteredPin.length > index;
                  return Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
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
              )
            else
              const Icon(Icons.lock_clock, color: AppColors.severityHigh, size: 40),

            const SizedBox(height: 20),
            
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isLockedOut ? AppColors.severityHigh : Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              
            const Spacer(),
            
            // Custom PIN Pad
            CustomPinPad(
              onKeyPressed: _handlePinKey,
              onDeletePressed: _handlePinDelete,
              onBiometricPressed: _authenticateBiometrics,
              showBiometric: showBiometric,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
