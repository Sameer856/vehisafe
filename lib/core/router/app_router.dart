import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/dashboard/dashboard_shell.dart';
import '../../features/dashboard/home_screen.dart';
import '../../features/monitoring/monitoring_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/alert/alert_screen.dart';
import '../../features/alert/pin_cancellation_screen.dart';
import '../../features/alert/alert_sent_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  final settings = ref.watch(appSettingsProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: settings.isOnboarded ? '/home' : '/onboarding',
    
    // Listen to onboarding changes to redirect dynamically
    redirect: (context, state) {
      final isOnboarding = state.matchedLocation == '/onboarding';
      final isOnboarded = ref.read(appSettingsProvider).isOnboarded;

      if (!isOnboarded && !isOnboarding) {
        return '/onboarding';
      }
      if (isOnboarded && isOnboarding) {
        return '/home';
      }
      return null;
    },

    routes: [
      // Onboarding Flow
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Navigation Shell (Dashboard, Monitoring, History, Settings)
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) {
          return DashboardShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/monitoring',
            builder: (context, state) => const MonitoringScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),

      // Full-screen Alert Screens
      GoRoute(
        path: '/alert',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const CustomTransitionPage(
          child: AlertScreen(),
          transitionsBuilder: _emergencyFadeTransition,
        ),
      ),
      GoRoute(
        path: '/alert-pin',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const CustomTransitionPage(
          child: PinCancellationScreen(),
          transitionsBuilder: _slideUpTransition,
        ),
      ),
      GoRoute(
        path: '/alert-sent',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const CustomTransitionPage(
          child: AlertSentScreen(),
          transitionsBuilder: _emergencyFadeTransition,
        ),
      ),
    ],
  );
});

// Custom urgent transition animations
Widget _emergencyFadeTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return FadeTransition(
    opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
    child: child,
  );
}

Widget _slideUpTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  );
}
