import 'dart:async';

/// Stub for non-web platforms.
Future<bool> requestWebNotificationPermission() async => false;

bool isWebNotificationSupported() => false;

void showWebNotification({
  required String title,
  required String body,
  String? tag,
  void Function()? onClick,
}) {}
