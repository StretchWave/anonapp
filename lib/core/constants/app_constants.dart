/// Application-wide constants.
abstract final class AppConstants {
  /// Application name displayed in the UI.
  static const String appName = 'AnonApp';

  /// The pseudo-email domain used for Supabase Auth.
  /// Usernames are mapped to `username@anonapp.internal` for auth.
  static const String authEmailDomain = 'anonapp.internal';

  /// Minimum username length.
  static const int usernameMinLength = 3;

  /// Maximum username length.
  static const int usernameMaxLength = 30;

  /// Minimum password length.
  static const int passwordMinLength = 8;

  /// Maximum display name length.
  static const int displayNameMaxLength = 50;

  /// Contact code length (alphanumeric).
  static const int contactCodeLength = 8;

  /// Number of messages to fetch per page.
  static const int messagesPageSize = 50;

  /// Typing indicator debounce duration.
  static const Duration typingDebounce = Duration(milliseconds: 500);

  /// Typing indicator auto-timeout (if stop event is never received).
  static const Duration typingTimeout = Duration(seconds: 5);

  /// Presence heartbeat interval.
  static const Duration presenceHeartbeat = Duration(seconds: 30);

  /// Reconnect retry delay.
  static const Duration reconnectDelay = Duration(seconds: 3);

  /// Maximum reconnect retries.
  static const int maxReconnectRetries = 10;

  /// Disappearing message duration options.
  static const Map<String, Duration?> disappearingDurations = {
    'Off': null,
    '30 seconds': Duration(seconds: 30),
    '5 minutes': Duration(minutes: 5),
    '1 hour': Duration(hours: 1),
    '24 hours': Duration(hours: 24),
    '7 days': Duration(days: 7),
  };
}
