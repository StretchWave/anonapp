/// Supabase table names, column names, and channel identifiers.
///
/// Centralised here so typos in string literals don't cause silent bugs.
abstract final class SupabaseConstants {
  // ── Table names ──────────────────────────────────────────────
  static const String profilesTable = 'profiles';
  static const String conversationsTable = 'conversations';
  static const String conversationMembersTable = 'conversation_members';
  static const String messagesTable = 'messages';
  static const String blocksTable = 'blocks';
  static const String reportsTable = 'reports';
  static const String userDevicesTable = 'user_devices';
  static const String userSessionsTable = 'user_sessions';

  // ── Realtime channels ────────────────────────────────────────
  static const String messagesChannel = 'realtime:messages';
  static const String presenceChannel = 'presence';
  static const String typingChannel = 'typing';

  // ── Realtime event types ─────────────────────────────────────
  static const String typingStartEvent = 'typing.start';
  static const String typingStopEvent = 'typing.stop';

  // ── Storage buckets ──────────────────────────────────────────
  // (reserved for future media support)
  static const String mediasBucket = 'medias';
}
