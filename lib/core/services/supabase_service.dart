import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';

/// Provides the Supabase client to the application via Riverpod.
///
/// Initialisation happens once in `main()` via [SupabaseService.initialize].
/// After that, the client is available through [supabaseClientProvider].
abstract final class SupabaseService {
  /// Initialise the Supabase SDK. Must be called before `runApp`.
  static Future<void> initialize() async {
    Env.validate();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  /// The Supabase client singleton.
  static SupabaseClient get client => Supabase.instance.client;
}

/// Riverpod provider for the Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});
