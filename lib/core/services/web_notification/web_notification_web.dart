import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Checks if the Web Notifications API is supported in the current browser.
bool isWebNotificationSupported() {
  try {
    return web.Notification.permission.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Requests browser permission to display desktop/system notifications.
Future<bool> requestWebNotificationPermission() async {
  try {
    if (!isWebNotificationSupported()) return false;
    final permission = await web.Notification.requestPermission().toDart;
    return permission.toDart == 'granted';
  } catch (e) {
    debugPrint('[WebNotification] Permission request error: $e');
    return false;
  }
}

/// Displays an HTML5 system notification via the browser.
void showWebNotification({
  required String title,
  required String body,
  String? tag,
  void Function()? onClick,
}) {
  try {
    if (!isWebNotificationSupported()) return;
    if (web.Notification.permission != 'granted') return;

    final options = web.NotificationOptions(
      body: body,
      icon: '/icons/Icon-192.png',
      tag: tag ?? 'anonapp_chat',
    );

    final notif = web.Notification(title, options);
    if (onClick != null) {
      notif.onclick = (web.Event _) {
        try {
          web.window.focus();
        } catch (_) {}
        onClick();
      }.toJS;
    }
  } catch (e) {
    debugPrint('[WebNotification] Error displaying notification: $e');
  }
}
