import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/colors.dart';
import '../../core/providers/app_providers.dart';

class AlertScreen extends ConsumerStatefulWidget {
  const AlertScreen({super.key});

  @override
  ConsumerState<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends ConsumerState<AlertScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertState = ref.watch(activeAlertStateProvider);
    
    // Redirect if alert state is cleared or sent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (alertState == null) {
        context.go('/home');
      } else if (alertState.isSent) {
        context.go('/alert-sent');
      }
    });

    if (alertState == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.red))),
      );
    }

    // Trigger haptic feedback tick on countdown decrement
    ref.listen<ActiveAlertState?>(activeAlertStateProvider, (previous, next) {
      if (next != null && previous != null && next.countdown != previous.countdown) {
        HapticFeedback.heavyImpact();
      }
    });

    final contacts = alertState.contactsNotified;
    final isHigh = alertState.severityLevel == 'HIGH';
    final isMedium = alertState.severityLevel == 'MEDIUM';

    Color severityColor = AppColors.severityLow;
    String modeDescription = 'CONTACTS ALERT';
    String detailsText = 'SMS alert dispatch will only be sent to registered contacts.';
    if (isMedium) {
      severityColor = AppColors.severityMedium;
      modeDescription = 'RESCUE ESCALATION';
      detailsText = 'Dispatches alerts to emergency services & registered contacts.';
    } else if (isHigh) {
      severityColor = AppColors.severityHigh;
      modeDescription = 'CRITICAL IMPACT ALERT';
      detailsText = 'Automated rescue routing & SMS emergency fallback activated.';
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Urgency Flashing Background
          _FlashingEmergencyBackground(severity: alertState.severityLevel),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  
                  // Siren Flashing Beacon Widget
                  SirenBeacon(severity: alertState.severityLevel),
                  
                  const SizedBox(height: 20),

                  // Severity Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: severityColor, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: severityColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${alertState.severityLevel} SEVERITY COLLISION',
                          style: TextStyle(
                            color: severityColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Pulsing Countdown Timer
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: severityColor.withValues(alpha: 0.05),
                        border: Border.all(color: severityColor.withValues(alpha: 0.5), width: 6),
                        boxShadow: [
                          BoxShadow(
                            color: severityColor.withValues(alpha: 0.15),
                            blurRadius: 30,
                            spreadRadius: 5,
                          )
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${alertState.countdown}',
                              style: const TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              'SECONDS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: severityColor,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Alert Status Header
                  Text(
                    modeDescription,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detailsText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // SMS Fallback Indicator Banner for HIGH Severity
                  if (isHigh)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cell_tower, color: Colors.red, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SMS CELLULAR FALLBACK ENGAGED',
                                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'GPS payload coordinates will send via USB Modem SMS fallback if LTE data fails.',
                                  style: TextStyle(color: Colors.white70, fontSize: 9),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),

                  // PIN-only notification warning for HIGH
                  if (isHigh)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, color: Colors.amber, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'PIN Authorization Required (Biometrics Disabled)',
                            style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                  // Notified Contacts list
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TARGET ALARM CONTACTS:',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),
                        if (contacts.isEmpty)
                          const Text('No emergency contacts registered', style: TextStyle(color: Colors.grey, fontSize: 12))
                        else
                          ...contacts.map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
                                    Text(c.phoneNumber, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                              )),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            context.push('/alert-pin');
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white, width: 1.5),
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('CANCEL ALARM', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(activeAlertStateProvider.notifier).sendAlert();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('SEND NOW', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          
          // Sending overlay
          if (alertState.isSending)
            Container(
              color: Colors.black.withValues(alpha: 0.9),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.red)),
                    SizedBox(height: 24),
                    Text(
                      'DISPATCHING LTE GPS ALARM...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Transmitting telemetry packet & routing SMS backup logs',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    )
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }
}

// Alternating Flashing Siren Lightbar
class SirenBeacon extends StatefulWidget {
  final String severity;
  const SirenBeacon({super.key, required this.severity});

  @override
  State<SirenBeacon> createState() => _SirenBeaconState();
}

class _SirenBeaconState extends State<SirenBeacon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // HIGH flashes much faster for extreme visual urgency
    final flashDuration = widget.severity == 'HIGH' ? const Duration(milliseconds: 300) : const Duration(milliseconds: 650);
    _controller = AnimationController(
      vsync: this,
      duration: flashDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertColor = widget.severity == 'HIGH'
        ? Colors.red
        : (widget.severity == 'MEDIUM' ? Colors.orange : Colors.green);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final isLeftActive = _controller.value < 0.5;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                color: isLeftActive ? alertColor : alertColor.withValues(alpha: 0.12),
                boxShadow: isLeftActive
                    ? [BoxShadow(color: alertColor.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 2)]
                    : [],
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 16,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Icon(Icons.campaign, size: 12, color: Colors.white),
            ),
            const SizedBox(width: 4),
            Container(
              width: 50,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                color: !isLeftActive ? Colors.blue : Colors.blue.withValues(alpha: 0.12),
                boxShadow: !isLeftActive
                    ? [BoxShadow(color: Colors.blue.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 2)]
                    : [],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Emergency Flashing Red-Shifted Cinematic Background
class _FlashingEmergencyBackground extends StatefulWidget {
  final String severity;
  const _FlashingEmergencyBackground({required this.severity});

  @override
  State<_FlashingEmergencyBackground> createState() => _FlashingEmergencyBackgroundState();
}

class _FlashingEmergencyBackgroundState extends State<_FlashingEmergencyBackground> with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    // Fast flash for HIGH, slower pulse for MEDIUM, standby slow for LOW
    final pulseDuration = widget.severity == 'HIGH'
        ? const Duration(milliseconds: 500)
        : (widget.severity == 'MEDIUM' ? const Duration(milliseconds: 1000) : const Duration(milliseconds: 2000));

    _bgController = AnimationController(
      vsync: this,
      duration: pulseDuration,
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.05, end: 0.35).animate(_bgController);
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertColor = widget.severity == 'HIGH'
        ? Colors.red
        : (widget.severity == 'MEDIUM' ? Colors.orange : Colors.green);

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black,
                alertColor.withValues(alpha: _glowAnimation.value),
                Colors.black,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        );
      },
    );
  }
}
