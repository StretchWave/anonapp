import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/env/env.dart';
import '../../../../core/services/encryption_service.dart';
import '../../../../core/services/foreground_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../conversations/domain/models/conversation.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import 'message_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Tracks whether the app is currently in the foreground (resumed).
final isAppResumedProvider = StateProvider<bool>((ref) => true);

/// Tracks the conversation currently open on screen so active chats do not trigger
/// redundant notifications while the user is actively viewing them in the foreground.
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
    _load();
  }

  static const _keyEnabled = 'notifications_enabled';
  static const _keyDiscreet = 'notifications_discreet';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? !kIsWeb;
    final discreet = prefs.getBool(_keyDiscreet) ?? false;
    state = NotificationSettings(enabled: enabled, discreet: discreet);
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

  /// Toggle discreet mode (hides sender name and message content).
  Future<void> setDiscreet(bool discreet) async {
    if (kIsWeb) return;
    state = state.copyWith(discreet: discreet);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiscreet, discreet);
  }
}

/// Background synchronization and lifecycle manager for mobile platforms.
/// Keeps WebSocket alive when minimized, reconnects proactively, and performs
/// fallback polling to guarantee notifications with sound even in background mode.
class BackgroundSyncManager with WidgetsBindingObserver {
  BackgroundSyncManager(this._ref, this._client);

  final Ref _ref;
  final SupabaseClient _client;
  Timer? _keepAliveTimer;
  final Set<String> _processedMessageIds = {};
  final Map<String, String> _usernameCache = {};

  ProviderSubscription<AsyncValue<List<Conversation>>>? _conversationsSub;

  void start() {
    _subscribeConversationsForUsernameCache();
    if (kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);
    _startKeepAliveLoop();
  }

  void _subscribeConversationsForUsernameCache() {
    _conversationsSub = _ref.listen<AsyncValue<List<Conversation>>>(
      conversationsProvider,
      (previous, next) {
        final list = next.valueOrNull;
        if (list != null) {
          for (final c in list) {
            if (c.otherMemberId != null && c.otherMemberUsername != null) {
              _usernameCache[c.otherMemberId!] = c.otherMemberUsername!;
            }
          }
        }
      },
      fireImmediately: true,
    );
  }

  void stop() {
    _conversationsSub?.close();
    if (kIsWeb) return;
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
    _keepAliveTimer?.cancel();
  }

  void _onForegroundTaskData(Object data) {
    if (data is Map && data['action'] == 'check_unread') {
      FlutterForegroundTask.sendDataToTask({'status': 'main_active'});
      unawaited(_checkUnreadMessages());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    final isResumed = state == AppLifecycleState.resumed;
    _ref.read(isAppResumedProvider.notifier).state = isResumed;

    if (!isResumed) {
      // Zeroize and wipe in-memory cryptographic key cache immediately upon minimize/screen lock
      EncryptionService.instance.clearKeyCache();
      // Clear active conversation ID so background messages trigger notifications properly
      _ref.read(activeConversationIdProvider.notifier).state = null;

      // App was minimized or moved to background
      Future.delayed(const Duration(milliseconds: 350), () {
        _reconnectRealtime();
        unawaited(_checkUnreadMessages());
      });
    } else {
      // Returned to foreground
      _reconnectRealtime();
      _ref.invalidate(conversationsProvider);
      unawaited(_checkUnreadMessages());
      final activeConvId = _ref.read(activeConversationIdProvider);
      if (activeConvId != null) {
        try {
          _ref
              .read(conversationMessagesProvider(activeConvId).notifier)
              .syncLatestMessages();
        } catch (_) {}
        NotificationService.instance
            .clearNotificationsForConversation(activeConvId);
      }
    }
  }

  void _startKeepAliveLoop() {
    _keepAliveTimer?.cancel();
    // Run keepalive every 8 seconds on mobile while in background
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      final isResumed = _ref.read(isAppResumedProvider);
      if (!isResumed) {
        _reconnectRealtime();
        await _checkUnreadMessages();
      }
    });
  }

  void _reconnectRealtime() {
    try {
      if (!_client.realtime.isConnected) {
        // Realtime channels automatically trigger socket connection on subscription
      }
    } catch (e) {
      debugPrint('[BackgroundSync] Realtime reconnect error: $e');
    }
  }

  Future<void> _checkUnreadMessages() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Rolling 10-minute window avoids dropping messages due to device/server clock drift
      final windowStart = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();

      final rows = await _client
          .from(SupabaseConstants.messagesTable)
          .select(
            'id, conversation_id, sender_id, content, message_type, created_at, client_id',
          )
          .neq('sender_id', currentUserId)
          .filter('read_at', 'is', null)
          .gt('created_at', windowStart)
          .order('created_at', ascending: true)
          .limit(20);

      for (final row in rows) {
        final id = row['id'] as String;
        if (_processedMessageIds.contains(id)) continue;
        _processedMessageIds.add(id);
        if (_processedMessageIds.length > 300) {
          _processedMessageIds.remove(_processedMessageIds.first);
        }

        // If this unread message belongs to the active conversation,
        // feed it directly to the message provider for instant UI update
        final convId = row['conversation_id'] as String?;
        final activeConv = _ref.read(activeConversationIdProvider);
        if (convId != null && activeConv == convId) {
          try {
            unawaited(
              _ref
                  .read(conversationMessagesProvider(convId).notifier)
                  .insertIncomingRecord(row),
            );
          } catch (_) {}
        }

        await dispatchNotificationForRecord(row);
      }
    } catch (e) {
      debugPrint('[BackgroundSync] Check unread error: $e');
    }
  }

  /// Dispatches a high-priority system notification with sound and vibration.
  Future<void> dispatchNotificationForRecord(
    Map<String, dynamic> record,
  ) async {
    final currentUserId = _client.auth.currentUser?.id;
    final senderId = record['sender_id'] as String?;
    final conversationId = record['conversation_id'] as String?;
    if (senderId == null || conversationId == null) return;
    if (senderId == currentUserId) return;

    final id = record['id'] as String?;
    if (id != null) {
      _processedMessageIds.add(id);
      if (_processedMessageIds.length > 300) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }
    }

    // Invalidate conversations list so unread counter updates in real time
    _ref.invalidate(conversationsProvider);

    // If active conversation matches, feed record directly to conversationMessagesProvider
    final activeConversation = _ref.read(activeConversationIdProvider);
    if (activeConversation == conversationId) {
      try {
        unawaited(
          _ref
              .read(conversationMessagesProvider(conversationId).notifier)
              .insertIncomingRecord(record),
        );
      } catch (_) {}
    }

    // UNDER NO CIRCUMSTANCES should the webapp get a notification or play sound
    if (kIsWeb) return;

    // Check if user is currently looking at this conversation in the FOREGROUND
    final isResumed = _ref.read(isAppResumedProvider);

    // ONLY suppress notification if the app is actively resumed AND looking at this exact chat
    if (isResumed && activeConversation == conversationId) {
      return;
    }

    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.enabled) return;

    String senderUsername = 'Anonymous';
    if (!settings.discreet) {
      if (_usernameCache.containsKey(senderId)) {
        senderUsername = _usernameCache[senderId]!;
      } else {
        try {
          final profile = await _client
              .from(SupabaseConstants.profilesTable)
              .select('username')
              .eq('id', senderId)
              .maybeSingle();
          if (profile != null && profile['username'] != null) {
            senderUsername = profile['username'] as String;
            _usernameCache[senderId] = senderUsername;
          }
        } catch (_) {}
      }
    }

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
          final rawContent = record['content'] as String? ?? 'New message';
          if (EncryptionService.isEncrypted(rawContent)) {
            body = await EncryptionService.instance.decryptText(
              rawContent,
              conversationId,
            );
          } else {
            body = rawContent;
          }
          break;
      }
    }

    // Group notifications by conversation/sender (like WhatsApp/Instagram).
    // The notification ID is deterministic per conversation, allowing incoming messages
    // to stack under this sender while still alerting with sound/vibration.
    final notifId =
        NotificationService.conversationNotificationId(conversationId);

    await NotificationService.instance.showMessageNotification(
      id: notifId,
      title: title,
      body: body,
      conversationId: conversationId,
      senderUsername: senderUsername,
      isDiscreet: settings.discreet,
    );
  }
}

/// Listens for real-time incoming messages to update conversations across Web and Mobile,
/// and dispatches system notifications with sound exclusively on mobile (Android/iOS).
/// UNDER NO CIRCUMSTANCES does the Web platform show notifications or play sounds.
final messageNotificationListenerProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);
  final isAuthenticated = authState.valueOrNull ?? false;
  if (!isAuthenticated) {
    if (!kIsWeb) {
      unawaited(AppForegroundService.instance.stop());
    }
    return;
  }

  final client = ref.watch(supabaseClientProvider);
  final currentUserId = client.auth.currentUser?.id;
  if (currentUserId == null) return;

  // Initialize notifications & foreground service exclusively on mobile (Android/iOS)
  if (!kIsWeb) {
    unawaited(NotificationService.instance.initialize());
    unawaited(NotificationService.instance.checkLaunchNotification());
    unawaited(AppForegroundService.instance.start(
      userId: currentUserId,
      supabaseUrl: Env.supabaseUrl,
      supabaseAnonKey: Env.supabaseAnonKey,
      authToken: client.auth.currentSession?.accessToken,
    ));
  }

  final syncManager = BackgroundSyncManager(ref, client);
  syncManager.start();

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
            await syncManager.dispatchNotificationForRecord(record);
          } catch (e) {
            debugPrint(
              '[NotificationListener] Error handling notification: $e',
            );
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: SupabaseConstants.messagesTable,
        callback: (payload) {
          try {
            final record = payload.newRecord;
            if (record.isNotEmpty && record['read_at'] != null) {
              final convId = record['conversation_id'] as String?;
              if (convId != null) {
                ref
                    .read(locallyReadConversationIdsProvider.notifier)
                    .update((s) => {...s, convId});
              }
            }
          } catch (_) {}
        },
      )
      .subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          debugPrint(
            '[NotificationListener] global_notifications channel status: $status ($error). Reconnecting...',
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (client.auth.currentUser != null) {
              channel.subscribe();
            }
          });
        }
      });

  ref.onDispose(() {
    syncManager.stop();
    channel.unsubscribe();
  });
});
