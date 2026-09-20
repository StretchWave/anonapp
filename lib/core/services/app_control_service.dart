import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'foreground_service.dart';

/// Service providing platform-level app lifecycle controls.
abstract final class AppControlService {
  static const MethodChannel _channel =
      MethodChannel('com.example.anonapp/app_control');

  /// Minimizes the app to the background without destroying the process on Android.
  static Future<void> minimizeApp() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      AppForegroundService.instance.minimizeApp();
    } catch (_) {
      try {
        await _channel.invokeMethod<bool>('minimizeApp');
      } catch (e) {
        debugPrint('[AppControlService] Error minimizing app: $e');
      }
    }
  }

  /// Disallows screenshots and screen recording on Android (FLAG_SECURE).
  static Future<void> enableSecureScreen() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('enableSecureScreen');
    } catch (e) {
      debugPrint('[AppControlService] Error enabling secure screen: $e');
    }
  }

  /// Restores normal screenshot and screen recording permissions on Android.
  static Future<void> disableSecureScreen() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('disableSecureScreen');
    } catch (e) {
      debugPrint('[AppControlService] Error disabling secure screen: $e');
    }
  }
}
