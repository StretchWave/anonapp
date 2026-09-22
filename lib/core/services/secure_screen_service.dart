import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to prevent screenshots and screen recordings during sensitive views
/// (such as view-once photos) by setting WindowManager.LayoutParams.FLAG_SECURE on Android.
class SecureScreenService {
  SecureScreenService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.anonapp/app_control',
  );

  /// Blocks screenshots and screen recordings on the current window.
  static Future<void> enableSecure() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('enableSecureScreen');
      }
    } catch (e) {
      debugPrint('[SecureScreenService] Error enabling secure screen: $e');
    }
  }

  /// Restores normal screenshot and screen recording permissions.
  static Future<void> disableSecure() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('disableSecureScreen');
      }
    } catch (e) {
      debugPrint('[SecureScreenService] Error disabling secure screen: $e');
    }
  }
}
