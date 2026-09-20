import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/foreground_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Supabase SDK (reads env from --dart-define / .env).
  await SupabaseService.initialize();

  // Initialize notifications and ensure persistent background notification is dismissed
  if (!kIsWeb) {
    AppForegroundService.instance.initialize();
    await AppForegroundService.instance.stop();
    await NotificationService.instance.initialize();
    await NotificationService.instance.requestPermissions();
  }

  runApp(const ProviderScope(child: AnonApp()));
}
