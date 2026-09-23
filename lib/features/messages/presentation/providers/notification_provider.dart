import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/services/encryption_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../conversations/domain/models/conversation.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import 'message_provider.dart';

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

/// Provider managing notification settings persisted in SharedPreferences and synced with Supabase.
final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      (ref) => NotificationSettingsNotifier(ref),
    );

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier(this._ref)
    : super(const NotificationSettings(enabled: !kIsWeb, discreet: false)) {
    _load();
  }

  final Ref _ref;
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
      await PushNotificationService.instance.requestPermission();
    } else {
      await NotificationService.instance.cancelAll();
    }

    state = state.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);

    // Sync state with Supabase device registry if user is logged in
    final client = _ref.read(supabaseClientProvider);
    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId != null) {
      await PushNotificationService.instance.syncDeviceRegistration(
        supabaseClient: client,
        userId: currentUserId,
        notificationsEnabled: enabled,
        isDiscreet: state.discreet,
      );
    }
    _ref.invalidate(pushNotificationStatusProvider);
  }

  /// Toggle discreet mode (hides sender name on lock screens).
  Future<void> setDiscreet(bool discreet) async {
    if (kIsWeb) return;
    state = state.copyWith(discreet: discreet);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiscreet, discreet);

    final client = _ref.read(supabaseClientProvider);
    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId != null) {
      await PushNotificationService.instance.syncDeviceRegistration(
        supabaseClient: client,
        userId: currentUserId,
        notificationsEnabled: state.enabled,
        isDiscreet: discreet,
      );
    }
  }
}

/// Provides detailed push notification status distinguishing OS permission,
/// app preference, FCM token state, and Supabase device synchronization.
final pushNotificationStatusProvider = FutureProvider<PushNotificationStatus>((
  ref,
) async {
  final settings = ref.watch(notificationSettingsProvider);
  return PushNotificationService.instance.getStatus(settings.enabled);
});

/// Manages background unread synchronization, active chat notification suppression,
/// and local notification dispatch for incoming messages across Mobile and Web.
///
/// NOTE: Strictly no notifications or sounds are dispatched on Web (kIsWeb).
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

    // Active conversation checker for PushNotificationService
    PushNotificationService.instance.activeConversationChecker = (convId) {
      final isResumed = _ref.read(isAppResumedProvider);
      final activeConvId = _ref.read(activeConversationIdProvider);
      return isResumed && activeConvId == convId;
    };

    // Ensure notification permissions are requested on mobile when UI starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.requestPermissions();
    });

    _syncCurrentDevice();
    _startKeepAliveLoop();
    unawaited(_checkUnreadMessages());
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
    PushNotificationService.instance.activeConversationChecker = null;
    _keepAliveTimer?.cancel();
  }

  void _syncCurrentDevice() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final settings = _ref.read(notificationSettingsProvider);
    unawaited(
      PushNotificationService.instance.syncDeviceRegistration(
        supabaseClient: _client,
        userId: userId,
        notificationsEnabled: settings.enabled,
        isDiscreet: settings.discreet,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    final isResumed = state == AppLifecycleState.resumed;
    _ref.read(isAppResumedProvider.notifier).state = isResumed;

    if (!isResumed) {
      // Zeroize and wipe in-memory cryptographic key cache immediately upon minimize/lock
      EncryptionService.instance.clearKeyCache();
      // Clear active conversation ID so background messages trigger notifications properly
      _ref.read(activeConversationIdProvider.notifier).state = null;
    } else {
      // Returned to foreground: re-check status and perform chat UI reconciliation
      _ref.invalidate(pushNotificationStatusProvider);
      _ref.invalidate(conversationsProvider);

      final activeConvId = _ref.read(activeConversationIdProvider);
      if (activeConvId != null) {
        try {
          _ref
              .read(conversationMessagesProvider(activeConvId).notifier)
              .syncLatestMessages();
        } catch (_) {}
        NotificationService.instance.clearNotificationsForConversation(
          activeConvId,
        );
      }

      unawaited(_checkUnreadMessages());
    }
  }

  void _startKeepAliveLoop() {
    _keepAliveTimer?.cancel();
    // Check for missed unread messages every 4 seconds as a reliable background fallback
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _checkUnreadMessages();
    });
  }

  Future<void> _checkUnreadMessages() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Rolling 10-minute window avoids dropping messages due to clock drift
      final windowStart = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();

      final rows = await _client
          .from(SupabaseConstants.messagesTable)
          .select(
            'id, conversation_id, sender_id, content, message_type, created_at, client_id, expires_at, deleted_at',
          )
          .neq('sender_id', currentUserId)
          .filter('read_at', 'is', null)
          .gt('created_at', windowStart)
          .order('created_at', ascending: true)
          .limit(20);

      for (final row in rows) {
        final id = row['id'] as String?;
        if (id != null && _processedMessageIds.contains(id)) continue;
        if (row['deleted_at'] != null) continue;

        final expiresAtStr = row['expires_at'] as String?;
        if (expiresAtStr != null) {
          final exp = DateTime.tryParse(expiresAtStr)?.toUtc();
          if (exp != null && DateTime.now().toUtc().isAfter(exp)) {
            continue;
          }
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

  /// Dispatches a high-priority system notification with sound and vibration on mobile devices.
  /// Strictly skips notifications and sounds on Web (kIsWeb).
  Future<void> dispatchNotificationForRecord(
    Map<String, dynamic> record,
  ) async {
    final currentUserId = _client.auth.currentUser?.id;
    final senderId = record['sender_id'] as String?;
    final conversationId = record['conversation_id'] as String?;
    if (senderId == null || conversationId == null) return;
    if (senderId == currentUserId) return;

    if (record['deleted_at'] != null) return;
    final expiresAtStr = record['expires_at'] as String?;
    if (expiresAtStr != null) {
      final exp = DateTime.tryParse(expiresAtStr)?.toUtc();
      if (exp != null && DateTime.now().toUtc().isAfter(exp)) {
        return;
      }
    }

    final id = record['id'] as String?;
    if (id != null) {
      if (_processedMessageIds.contains(id)) return;
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
      debugPrint(
        '[BackgroundSync] Suppressing notification: user actively viewing conv $conversationId',
      );
      return;
    }

    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.enabled) {
      debugPrint('[BackgroundSync] Notification skipped: disabled in settings');
      return;
    }

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
        case 'document':
          body = '📄 Document';
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

    final notifId =
        NotificationService.conversationNotificationId(conversationId);

    debugPrint(
      '[BackgroundSync] Dispatching notification $notifId for @$senderUsername: "$body"',
    );

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

  final client = ref.watch(supabaseClientProvider);
  final currentUserId = client.auth.currentUser?.id;

  if (!isAuthenticated || currentUserId == null) {
    if (!kIsWeb && currentUserId != null) {
      unawaited(
        PushNotificationService.instance.deactivateDevice(
          client,
          currentUserId,
        ),
      );
    }
    return;
  }

  // Initialize notifications on mobile (Android/iOS)
  if (!kIsWeb) {
    unawaited(NotificationService.instance.initialize());
    unawaited(NotificationService.instance.checkLaunchNotification());
  }

  final syncManager = BackgroundSyncManager(ref, client);
  syncManager.start();

  // Realtime channel for incoming message notifications & UI synchronization
  // Scoped uniquely to currentUserId to avoid multi-device topic collisions
  final channel = client.channel('user_notif_$currentUserId');

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: SupabaseConstants.messagesTable,
        callback: (payload) async {
          try {
            final record = payload.newRecord;
            if (record.isEmpty) return;
            debugPrint(
              '[NotificationListener] PostgresChanges insert received: ${record['id']}',
            );
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
        debugPrint(
          '[NotificationListener] Channel user_notif_$currentUserId status: $status ($error)',
        );
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          debugPrint(
            '[NotificationListener] Channel status: $status ($error). Reconnecting...',
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
