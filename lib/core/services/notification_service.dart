import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../routing/app_router.dart';

/// Service managing system notifications on Android and iOS.
/// Completely disabled on the Web platform.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId = 'anonapp_messages_v5';
  static const String _channelName = 'Incoming Messages';
  static const String _channelDescription =
      'High-priority sound and vibration notifications for incoming anonymous messages';

  /// Initialize local notification plugins and channel for Android and iOS.
  /// Strictly no-op on Web.
  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Create Android High-Priority Notification Channel
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      // Clean up legacy lower-importance channels to prevent Android caching issues
      try {
        await androidImplementation.deleteNotificationChannel(
          channelId: 'anonapp_messages',
        );
        await androidImplementation.deleteNotificationChannel(
          channelId: 'anonapp_messages_v2',
        );
        await androidImplementation.deleteNotificationChannel(
          channelId: 'anonapp_messages_v4',
        );
        await androidImplementation.deleteNotificationChannel(
          channelId: 'anonapp_bg_service',
        );
        await androidImplementation.deleteNotificationChannel(
          channelId: 'anonapp_bg_service_v2',
        );
        await androidImplementation.deleteNotificationChannel(
          channelId: 'anonapp_bg_service_v3',
        );
        await androidImplementation.deleteNotificationChannel(
          channelId: 'anonapp_bg_service_v4',
        );
        await androidImplementation.cancel(id: 256);
      } catch (_) {}

      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }

    _initialized = true;
  }

  /// Android notification group key used to cluster all AnonApp notifications into a single attached stack.
  static const String groupKey = 'com.example.anonapp.MESSAGES';

  /// Notification ID reserved for the Android group summary card.
  static const int summaryNotificationId = 0;

  /// Generates a consistent 31-bit positive notification ID for a conversation.
  static int conversationNotificationId(String conversationId) {
    return conversationId.hashCode & 0x7FFFFFFF;
  }

  /// In-memory cache of stacked unread message lines per conversation.
  final Map<String, List<String>> _conversationMessageLines = {};

  /// In-memory cache of seen message IDs per conversation to prevent duplicate notification stacking.
  final Map<String, Set<String>> _conversationMessageIds = {};

  /// In-memory map of latest sender username per conversation.
  final Map<String, String> _conversationUsernames = {};

  /// In-memory map of discreet mode setting per conversation.
  final Map<String, bool> _conversationDiscreet = {};

  final Map<String, Set<int>> _activeConversationNotificationIds = {};

  /// Global set of recently notified message IDs to guarantee deduplication
  /// between Supabase Realtime, FCM background handler, and FCM foreground handler.
  final Set<String> _globallyNotifiedMessageIds = {};

  /// Checks if a message ID has already generated a notification.
  bool hasNotifiedMessage(String messageId) =>
      _globallyNotifiedMessageIds.contains(messageId);

  @visibleForTesting
  List<String> getConversationLines(String conversationId) =>
      List.unmodifiable(_conversationMessageLines[conversationId] ?? const []);

  @visibleForTesting
  void resetConversationLines(String conversationId) {
    _conversationMessageLines.remove(conversationId);
    _conversationMessageIds.remove(conversationId);
    _conversationUsernames.remove(conversationId);
    _conversationDiscreet.remove(conversationId);
  }

  /// Request system notification permissions on Android (13+) and iOS.
  /// Returns true if granted or on unsupported platforms, false if explicitly denied.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidImplementation
          ?.requestNotificationsPermission();
      return granted ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosImplementation?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  /// Check if the application was cold-launched from a notification tap.
  Future<void> checkLaunchNotification() async {
    if (kIsWeb) return;
    try {
      final launchDetails = await _notificationsPlugin
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchDetails?.notificationResponse != null) {
        _handleNotificationTap(launchDetails!.notificationResponse!);
      }
    } catch (e) {
      debugPrint(
        '[NotificationService] Error checking launch notification: $e',
      );
    }
  }

  /// Display a stacked local notification for an incoming message under its conversation/sender.
  /// Strictly no-ops on Web.
  Future<void> showMessageNotification({
    int? id,
    required String title,
    required String body,
    String? conversationId,
    String? senderUsername,
    String? messageId,
    bool isDiscreet = false,
  }) async {
    if (kIsWeb) return;

    // 1. Global deduplication: Skip if this specific message was already notified
    if (messageId != null) {
      if (_globallyNotifiedMessageIds.contains(messageId)) {
        debugPrint(
          '[NotificationService] Message $messageId already notified, skipping duplicate',
        );
        return;
      }
      _globallyNotifiedMessageIds.add(messageId);
      if (_globallyNotifiedMessageIds.length > 500) {
        _globallyNotifiedMessageIds.remove(_globallyNotifiedMessageIds.first);
      }
    }

    if (!_initialized) {
      await initialize();
    }

    final notifId =
        id ??
        (conversationId != null
            ? conversationNotificationId(conversationId)
            : (body.hashCode & 0x7FFFFFFF));

    if (conversationId != null) {
      if (senderUsername != null && senderUsername.isNotEmpty) {
        _conversationUsernames[conversationId] = senderUsername;
      }
      _conversationDiscreet[conversationId] = isDiscreet;

      _activeConversationNotificationIds
          .putIfAbsent(conversationId, () => <int>{})
          .add(notifId);

      final messageIds = _conversationMessageIds.putIfAbsent(
        conversationId,
        () => <String>{},
      );

      final lines = _conversationMessageLines.putIfAbsent(
        conversationId,
        () => <String>[],
      );

      // Only add to preview lines if this messageId has not already been added
      if (messageId == null || !messageIds.contains(messageId)) {
        if (messageId != null) messageIds.add(messageId);
        lines.add(body);
        if (lines.length > 7) {
          lines.removeAt(0); // Cap at 7 most recent lines
        }
      }
    }

    final currentLines = conversationId != null
        ? (_conversationMessageLines[conversationId] ?? [body])
        : [body];
    final unreadCount = currentLines.length;

    String contentTitle;
    if (isDiscreet) {
      contentTitle = unreadCount > 1
          ? 'AnonApp ($unreadCount messages)'
          : 'AnonApp';
    } else if (senderUsername != null && senderUsername.isNotEmpty) {
      contentTitle = unreadCount > 1
          ? '@$senderUsername ($unreadCount)'
          : '@$senderUsername';
    } else {
      contentTitle = unreadCount > 1 ? '$title ($unreadCount)' : title;
    }

    final styleInfo = InboxStyleInformation(
      isDiscreet
          ? [
              unreadCount > 1
                  ? '$unreadCount new messages'
                  : 'New message received',
            ]
          : List<String>.from(currentLines),
      contentTitle: contentTitle,
      summaryText:
          '$unreadCount new ${unreadCount == 1 ? 'message' : 'messages'}',
    );

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
      channelShowBadge: true,
      onlyAlertOnce: false,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      fullScreenIntent: false,
      icon: '@mipmap/ic_launcher',
      ticker: contentTitle,
      groupKey: groupKey,
      groupAlertBehavior: GroupAlertBehavior.children,
      styleInformation: styleInfo,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'anonapp_messages',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    String? payload;
    if (conversationId != null) {
      payload = jsonEncode({
        'conversationId': conversationId,
        'username': senderUsername ?? '',
      });
    }

    try {
      await _notificationsPlugin.show(
        id: notifId,
        title: contentTitle,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
      debugPrint(
        '[NotificationService] Notification displayed successfully: id=$notifId title="$contentTitle" body="$body"',
      );

      // Refresh the group summary so all notifications remain attached together
      await _updateGroupSummaryNotification();
    } catch (e, st) {
      debugPrint(
        '[NotificationService] Error displaying notification: $e\n$st',
      );
    }
  }

  /// Updates or cancels the Android notification group summary card.
  /// All child notifications share [groupKey], so Android attaches them
  /// together into a single clustered notification card in the shade.
  Future<void> _updateGroupSummaryNotification() async {
    if (kIsWeb) return;

    final activeEntries = _conversationMessageLines.entries
        .where((e) => e.value.isNotEmpty)
        .toList();

    if (activeEntries.isEmpty) {
      try {
        await _notificationsPlugin.cancel(id: summaryNotificationId);
      } catch (_) {}
      return;
    }

    final List<String> summaryLines = [];
    int totalMessages = 0;

    for (final entry in activeEntries) {
      final convId = entry.key;
      final lines = entry.value;
      totalMessages += lines.length;
      final username = _conversationUsernames[convId] ?? 'Anonymous';
      final isDiscreet = _conversationDiscreet[convId] ?? false;
      final latestLine = lines.isNotEmpty ? lines.last : 'New message';

      if (isDiscreet) {
        summaryLines.add('AnonApp: $latestLine');
      } else {
        summaryLines.add('@$username: $latestLine');
      }
    }

    final chatCount = activeEntries.length;
    final summarySubText = chatCount == 1
        ? '$totalMessages ${totalMessages == 1 ? 'message' : 'messages'}'
        : '$chatCount ${chatCount == 1 ? 'chat' : 'chats'} • $totalMessages ${totalMessages == 1 ? 'message' : 'messages'}';

    final summaryStyle = InboxStyleInformation(
      summaryLines,
      contentTitle: 'AnonApp',
      summaryText: summarySubText,
    );

    final summaryAndroidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      icon: '@mipmap/ic_launcher',
      groupKey: groupKey,
      setAsGroupSummary: true,
      groupAlertBehavior: GroupAlertBehavior.children,
      styleInformation: summaryStyle,
    );

    final summaryDetails = NotificationDetails(
      android: summaryAndroidDetails,
      iOS: const DarwinNotificationDetails(
        threadIdentifier: 'anonapp_messages',
      ),
    );

    final summaryPayload = jsonEncode({'type': 'summary'});

    try {
      await _notificationsPlugin.show(
        id: summaryNotificationId,
        title: 'AnonApp',
        body: summarySubText,
        notificationDetails: summaryDetails,
        payload: summaryPayload,
      );
    } catch (e) {
      debugPrint('[NotificationService] Error updating group summary: $e');
    }
  }

  /// Cancel active notifications for a specific conversation and clear stacked history.
  Future<void> clearNotificationsForConversation(String conversationId) async {
    _conversationMessageLines.remove(conversationId);
    _conversationMessageIds.remove(conversationId);
    _conversationUsernames.remove(conversationId);
    _conversationDiscreet.remove(conversationId);
    if (kIsWeb) return;

    final convNotifId = conversationNotificationId(conversationId);
    try {
      await _notificationsPlugin.cancel(id: convNotifId);
    } catch (_) {}

    final ids = _activeConversationNotificationIds.remove(conversationId);
    if (ids != null && ids.isNotEmpty) {
      for (final id in ids) {
        try {
          await _notificationsPlugin.cancel(id: id);
        } catch (_) {}
      }
    }

    // Refresh or cancel the group summary
    await _updateGroupSummaryNotification();
  }

  /// Cancel all active notifications.
  Future<void> cancelAll() async {
    if (kIsWeb) return;
    _conversationMessageLines.clear();
    _conversationMessageIds.clear();
    _conversationUsernames.clear();
    _conversationDiscreet.clear();
    _activeConversationNotificationIds.clear();
    _globallyNotifiedMessageIds.clear();
    await _notificationsPlugin.cancelAll();
  }

  /// Handler when a user taps on a local notification.
  void _handleNotificationTap(NotificationResponse response) {
    final payloadString = response.payload;
    if (payloadString == null || payloadString.isEmpty) return;

    try {
      final data = jsonDecode(payloadString) as Map<String, dynamic>;

      // If user tapped the Group Summary notification, take them to the chats overview
      if (data['type'] == 'summary') {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          context.go('/conversations');
        } else {
          _queueNavigationPath('/conversations');
        }
        return;
      }

      final conversationId =
          (data['conversationId'] ?? data['conversation_id']) as String?;
      final username =
          (data['username'] ?? data['sender_username'] ?? '') as String;

      if (conversationId != null && conversationId.isNotEmpty) {
        clearNotificationsForConversation(conversationId);
        final encodedUsername = Uri.encodeComponent(username);
        final targetPath = '/chat/$conversationId?username=$encodedUsername';

        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          context.push(targetPath);
        } else {
          _queueNavigationPath(targetPath);
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Error handling notification tap: $e');
    }
  }

  void _queueNavigationPath(String targetPath) {
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 250), (timer) {
      attempts++;
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        timer.cancel();
        if (targetPath == '/conversations') {
          ctx.go(targetPath);
        } else {
          ctx.push(targetPath);
        }
      } else if (attempts >= 10) {
        timer.cancel();
      }
    });
  }
}
