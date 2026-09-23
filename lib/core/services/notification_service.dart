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
  /// No-op on Web.
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
        await androidImplementation.deleteNotificationChannel(channelId: 'anonapp_messages');
        await androidImplementation.deleteNotificationChannel(channelId: 'anonapp_messages_v2');
        await androidImplementation.deleteNotificationChannel(channelId: 'anonapp_messages_v4');
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

      // Proactively prompt for notification permission on Android 13+ (API 33+)
      try {
        await androidImplementation.requestNotificationsPermission();
      } catch (e) {
        debugPrint(
          '[NotificationService] Error requesting notification permissions: $e',
        );
      }
    }

    _initialized = true;
  }

  /// Generates a consistent 31-bit positive notification ID for a conversation.
  static int conversationNotificationId(String conversationId) {
    return conversationId.hashCode & 0x7FFFFFFF;
  }

  /// In-memory cache of stacked unread message lines per conversation.
  final Map<String, List<String>> _conversationMessageLines = {};

  final Map<String, Set<int>> _activeConversationNotificationIds = {};

  @visibleForTesting
  List<String> getConversationLines(String conversationId) =>
      List.unmodifiable(_conversationMessageLines[conversationId] ?? const []);

  @visibleForTesting
  void resetConversationLines(String conversationId) =>
      _conversationMessageLines.remove(conversationId);

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
    bool isDiscreet = false,
  }) async {
    if (kIsWeb) return;

    if (!_initialized) {
      await initialize();
    }

    final notifId =
        id ??
        (conversationId != null
            ? ((conversationId.hashCode ^ DateTime.now().microsecondsSinceEpoch) & 0x7FFFFFFF)
            : (body.hashCode & 0x7FFFFFFF));

    if (conversationId != null) {
      _activeConversationNotificationIds
          .putIfAbsent(conversationId, () => <int>{})
          .add(notifId);

      // Stack message preview line
      final lines = _conversationMessageLines.putIfAbsent(
        conversationId,
        () => <String>[],
      );
      lines.add(body);
      if (lines.length > 7) {
        lines.removeAt(0); // Cap at 7 most recent lines
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

    final groupKey =
        conversationId != null ? 'anonapp_conv_$conversationId' : null;

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
      fullScreenIntent: false,
      icon: '@mipmap/ic_launcher',
      ticker: contentTitle,
      groupKey: groupKey,
      styleInformation: styleInfo,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: conversationId != null
          ? 'anonapp_conv_$conversationId'
          : null,
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
    } catch (e, st) {
      debugPrint('[NotificationService] Error displaying notification: $e\n$st');
    }
  }

  /// Cancel active notifications for a specific conversation and clear stacked history.
  Future<void> clearNotificationsForConversation(String conversationId) async {
    if (kIsWeb) return;
    _conversationMessageLines.remove(conversationId);

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
  }

  /// Cancel all active notifications.
  Future<void> cancelAll() async {
    if (kIsWeb) return;
    _conversationMessageLines.clear();
    _activeConversationNotificationIds.clear();
    await _notificationsPlugin.cancelAll();
  }

  /// Handler when a user taps on a local notification.
  void _handleNotificationTap(NotificationResponse response) {
    final payloadString = response.payload;
    if (payloadString == null || payloadString.isEmpty) return;

    try {
      final data = jsonDecode(payloadString) as Map<String, dynamic>;
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
          int attempts = 0;
          Timer.periodic(const Duration(milliseconds: 250), (timer) {
            attempts++;
            final ctx = rootNavigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              timer.cancel();
              ctx.push(targetPath);
            } else if (attempts >= 10) {
              timer.cancel();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Error handling notification tap: $e');
    }
  }
}
