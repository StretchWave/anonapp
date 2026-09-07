/// Environment configuration for the application.
///
/// Supabase credentials can be provided via `--dart-define` at build time:
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=xxx
/// ```
///
/// Or via a `.env` file:
/// ```
/// flutter run --dart-define-from-file=.env
/// ```
///
/// If not supplied via command line, configured defaults are used.
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://oydrnjrtmaqvpylqrkfp.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_XvPGW6LkudxG1yULncAt4Q_z8ZJDqQx',
  );

  /// Validates that all required environment variables are set.
  static void validate() {
    if (supabaseUrl.isEmpty) {
      throw StateError(
        'SUPABASE_URL is not set. '
        'Pass it via --dart-define=SUPABASE_URL=... or --dart-define-from-file=.env',
      );
    }
    if (supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY is not set. '
        'Pass it via --dart-define=SUPABASE_ANON_KEY=... or --dart-define-from-file=.env',
      );
    }
  }
}
