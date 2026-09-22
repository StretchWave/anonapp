import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/notification_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Supabase SDK (reads env from --dart-define / .env).
  await SupabaseService.initialize();

  // Initialize notifications and FCM exclusively on mobile (Android / iOS)
  if (!kIsWeb) {
    await NotificationService.instance.initialize();
    await PushNotificationService.instance.initialize();
  }

  runApp(const ProviderScope(child: AnonApp()));
}
