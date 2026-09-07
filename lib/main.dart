import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Supabase SDK (reads env from --dart-define / .env).
  await SupabaseService.initialize();

  runApp(
    const ProviderScope(
      child: AnonApp(),
    ),
  );
}
