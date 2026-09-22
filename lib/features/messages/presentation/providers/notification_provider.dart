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

/// Lifecycle and session observer ensuring FCM tokens are registered on login,
/// deactivated on logout, and synchronized when returning to foreground.
class PushLifecycleCoordinator with WidgetsBindingObserver {
  PushLifecycleCoordinator(this._ref, this._client);

  final Ref _ref;
  final SupabaseClient _client;

  void start() {
    if (kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);

    // Link active conversation checker for active-chat notification suppression
    PushNotificationService.instance.activeConversationChecker = (convId) {
      final isResumed = _ref.read(isAppResumedProvider);
      final activeConvId = _ref.read(activeConversationIdProvider);
      return isResumed && activeConvId == convId;
    };

    // Initial sync
    _syncCurrentDevice();
  }

  void stop() {
    if (kIsWeb) return;
    WidgetsBinding.instance.removeObserver(this);
    PushNotificationService.instance.activeConversationChecker = null;
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
    }
  }
}

/// Activates FCM push notification registration, token lifecycle, and Realtime UI synchronization.
///
/// ARCHITECTURAL SEPARATION:
/// - Firebase Cloud Messaging (FCM) = Push notification transport across all app lifecycle states
/// - Supabase Realtime = In-app UI synchronization (chat updates, read receipts, typing) ONLY
///
/// Under NO circumstances does Realtime create system notifications or play sounds.
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

  // Mobile push registration & lifecycle coordination
  if (!kIsWeb) {
    final coordinator = PushLifecycleCoordinator(ref, client);
    coordinator.start();
    ref.onDispose(coordinator.stop);
  }

  // Realtime channel for live UI chat synchronization (NEVER for system notifications)
  final channel = client.channel('realtime_ui_sync');

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: SupabaseConstants.messagesTable,
        callback: (payload) {
          try {
            final record = payload.newRecord;
            if (record.isEmpty) return;

            // Invalidate conversations list so unread badges update in UI
            ref.invalidate(conversationsProvider);

            // If user is actively reading this conversation, feed record directly to conversation provider
            final convId = record['conversation_id'] as String?;
            final activeConv = ref.read(activeConversationIdProvider);
            if (convId != null && activeConv == convId) {
              try {
                unawaited(
                  ref
                      .read(conversationMessagesProvider(convId).notifier)
                      .insertIncomingRecord(record),
                );
              } catch (_) {}
            }
          } catch (e) {
            debugPrint('[RealtimeUI] Error updating UI from insert: $e');
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
            '[RealtimeUI] Channel status: $status ($error). Reconnecting...',
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (client.auth.currentUser != null) {
              channel.subscribe();
            }
          });
        }
      });

  ref.onDispose(() {
    channel.unsubscribe();
  });
});
