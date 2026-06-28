import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/app_providers.dart';
import 'core/services/storage_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Storage Service (Hive + SharedPreferences)
  final storageService = await StorageService.init();

  // Initialize Notification Service
  final notificationService = NotificationService();
  await notificationService.init();

  // Initialize Background Telemetry Service (Option A)
  await BackgroundServiceManager.initializeService();

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const VehiSafeApp(),
    ),
  );
}

class VehiSafeApp extends ConsumerWidget {
  const VehiSafeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'VehiSafe Control Panel',
      debugShowCheckedModeBanner: false,
      
      // Theme settings
      themeMode: ThemeMode.dark, // Default to premium dark theme
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.lightTheme,
      
      // Routing settings
      routerConfig: router,
    );
  }
}
