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

  static const String _channelId = 'anonapp_messages';
  static const String _channelName = 'Direct Messages';
  static const String _channelDescription =
      'Notifications for incoming anonymous messages';

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

    // Create Android High Importance Notification Channel
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
    }

    _initialized = true;
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

  /// Display a local notification for an incoming message.
  /// Strictly no-ops on Web.
  Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
    String? conversationId,
    String? senderUsername,
  }) async {
    if (kIsWeb) return;

    if (!_initialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
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

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Cancel all active notifications.
  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _notificationsPlugin.cancelAll();
  }

  /// Handler when a user taps on a notification.
  void _handleNotificationTap(NotificationResponse response) {
    final payloadString = response.payload;
    if (payloadString == null || payloadString.isEmpty) return;

    try {
      final data = jsonDecode(payloadString) as Map<String, dynamic>;
      final conversationId = data['conversationId'] as String?;
      final username = data['username'] as String? ?? '';

      if (conversationId != null && conversationId.isNotEmpty) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          context.push('/chat/$conversationId?username=$username');
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Error handling notification tap: $e');
    }
  }
}
