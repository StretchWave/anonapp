import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Tracks the conversation currently open on screen so active chats do not trigger
/// redundant notifications.
final activeConversationIdProvider = StateProvider<String?>((ref) => null);

/// User notification preferences.
class NotificationSettings {
  const NotificationSettings({required this.enabled, required this.discreet});

  final bool enabled;
  final bool discreet;

  NotificationSettings copyWith({bool? enabled, bool? discreet}) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      discreet: discreet ?? this.discreet,
    );
  }
}

/// Provider managing notification settings persisted in SharedPreferences.
final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      (ref) => NotificationSettingsNotifier(),
    );

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier()
    : super(const NotificationSettings(enabled: !kIsWeb, discreet: false)) {
    _loadSettings();
  }

  static const _keyEnabled = 'notifications_enabled';
  static const _keyDiscreet = 'notifications_discreet';

  Future<void> _loadSettings() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_keyEnabled) ?? true;
      final discreet = prefs.getBool(_keyDiscreet) ?? false;
      state = NotificationSettings(enabled: enabled, discreet: discreet);
    } catch (_) {}
  }

  /// Toggle notification enabled status. Requests OS permissions when enabling.
  Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    if (enabled) {
      await NotificationService.instance.requestPermissions();
    }
    state = state.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  /// Toggle discreet mode (hides sender and preview on lock screen).
  Future<void> setDiscreet(bool discreet) async {
    if (kIsWeb) return;
    state = state.copyWith(discreet: discreet);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiscreet, discreet);
  }
}

/// Listens for real-time incoming messages on Android and iOS to dispatch system notifications.
/// Strictly no-ops on the Web platform.
final messageNotificationListenerProvider = Provider<void>((ref) {
  if (kIsWeb) return;

  final authState = ref.watch(authStateProvider);
  final isAuthenticated = authState.valueOrNull ?? false;
  if (!isAuthenticated) return;

  final client = ref.watch(supabaseClientProvider);
  final currentUserId = client.auth.currentUser?.id;
  if (currentUserId == null) return;

  // Initialize service on startup
  unawaited(NotificationService.instance.initialize());

  // Cache for username lookups
  final usernameCache = <String, String>{};

  final channel = client.channel('global_notifications');

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: SupabaseConstants.messagesTable,
        callback: (payload) async {
          try {
            final record = payload.newRecord;
            if (record.isEmpty) return;

            final senderId = record['sender_id'] as String?;
            final conversationId = record['conversation_id'] as String?;
            if (senderId == null ||
                conversationId == null ||
                senderId == currentUserId) {
              return;
            }

            // Check if user is currently looking at this conversation
            final activeConversation = ref.read(activeConversationIdProvider);
            if (activeConversation == conversationId) {
              return;
            }

            // Check user settings
            final settings = ref.read(notificationSettingsProvider);
            if (!settings.enabled) {
              return;
            }

            // Fetch sender username if not cached and not in discreet mode
            String senderUsername = 'Anonymous';
            if (!settings.discreet) {
              if (usernameCache.containsKey(senderId)) {
                senderUsername = usernameCache[senderId]!;
              } else {
                try {
                  final profile = await client
                      .from(SupabaseConstants.profilesTable)
                      .select('username')
                      .eq('id', senderId)
                      .maybeSingle();
                  if (profile != null && profile['username'] != null) {
                    senderUsername = profile['username'] as String;
                    usernameCache[senderId] = senderUsername;
                  }
                } catch (_) {}
              }
            }

            // Construct notification title and content
            String title;
            String body;

            if (settings.discreet) {
              title = 'AnonApp';
              body = 'New message received';
            } else {
              title = '@$senderUsername';
              final msgType = record['message_type'] as String? ?? 'text';
              switch (msgType) {
                case 'image':
                  body = '📷 Photo';
                  break;
                case 'view_once_image':
                  body = '🔒 Photo (View once)';
                  break;
                case 'audio':
                  body = '🎤 Voice message';
                  break;
                default:
                  body = record['content'] as String? ?? 'New message';
                  break;
              }
            }

            final notifId = conversationId.hashCode & 0x7FFFFFFF;

            await NotificationService.instance.showMessageNotification(
              id: notifId,
              title: title,
              body: body,
              conversationId: conversationId,
              senderUsername: senderUsername,
            );
          } catch (e) {
            debugPrint(
              '[NotificationListener] Error handling notification: $e',
            );
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
  });
});
