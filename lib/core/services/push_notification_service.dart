import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';
import '../constants/supabase_constants.dart';
import '../routing/app_router.dart';
import 'notification_service.dart';

/// Top-level background message handler required by FCM.
/// Must be annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // In background or terminated state, Android system tray places the notification
  // directly from the FCM notification payload. We strictly DO NOT create a second
  // duplicate local notification here.
  debugPrint(
    '[FCM] Background message received: ${message.messageId} '
    '(conv: ${message.data['conversation_id']})',
  );
}

/// Status model distinguishing app preference, OS permission, token state, and Supabase sync.
class PushNotificationStatus {
  const PushNotificationStatus({
    required this.appPreferenceEnabled,
    required this.osPermissionGranted,
    required this.fcmTokenAvailable,
    required this.isSynced,
    this.maskedToken,
    this.lastSyncTime,
    this.error,
  });

  final bool appPreferenceEnabled;
  final bool osPermissionGranted;
  final bool fcmTokenAvailable;
  final bool isSynced;
  final String? maskedToken;
  final DateTime? lastSyncTime;
  final String? error;

  PushNotificationStatus copyWith({
    bool? appPreferenceEnabled,
    bool? osPermissionGranted,
    bool? fcmTokenAvailable,
    bool? isSynced,
    String? maskedToken,
    DateTime? lastSyncTime,
    String? error,
  }) {
    return PushNotificationStatus(
      appPreferenceEnabled: appPreferenceEnabled ?? this.appPreferenceEnabled,
      osPermissionGranted: osPermissionGranted ?? this.osPermissionGranted,
      fcmTokenAvailable: fcmTokenAvailable ?? this.fcmTokenAvailable,
      isSynced: isSynced ?? this.isSynced,
      maskedToken: maskedToken ?? this.maskedToken,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      error: error ?? this.error,
    );
  }
}

/// Core service managing Firebase Cloud Messaging (FCM) registration,
/// token synchronization with Supabase, active-chat suppression, and deep linking.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const String _prefInstallationIdKey = 'anonapp_installation_id';

  bool _initialized = false;
  String? _installationId;
  String? _currentFcmToken;
  String? _registeredUserId;
  DateTime? _lastSyncTime;

  /// The currently registered user ID in the device registry.
  String? get registeredUserId => _registeredUserId;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;

  /// Function hook used to check if a specific conversation is currently active on screen.
  bool Function(String conversationId)? activeConversationChecker;

  /// Pending navigation target if notification was tapped before navigator was mounted.
  String? _pendingNavigationPath;

  /// Returns masked representation of a token for safe diagnostic logging (e.g. `cK8s1a...3f9e`).
  static String maskToken(String? token) {
    if (token == null || token.isEmpty) return 'none';
    if (token.length <= 10) return '***';
    return '${token.substring(0, 6)}...${token.substring(token.length - 4)}';
  }

  /// Initialize Firebase & FCM handlers. Strictly a no-op on Web.
  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    try {
      debugPrint('[Push] Initializing Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Register top-level background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Load or generate stable installation ID
      final prefs = await SharedPreferences.getInstance();
      var instId = prefs.getString(_prefInstallationIdKey);
      if (instId == null || instId.isEmpty) {
        instId = const Uuid().v4();
        await prefs.setString(_prefInstallationIdKey, instId);
      }
      _installationId = instId;

      // Handle FCM messages arriving while the app is in the FOREGROUND
      _onMessageSub = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );

      // Handle FCM notification taps when app was in background
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleNotificationTap,
      );

      // Check for cold-start launch via FCM notification
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '[Push] Cold start from FCM notification: ${initialMessage.messageId}',
        );
        _handleNotificationTap(initialMessage);
      }

      _initialized = true;
      debugPrint('[Push] PushNotificationService initialized successfully.');
    } catch (e) {
      debugPrint('[Push] Error initializing PushNotificationService: $e');
    }
  }

  /// Request notification permission on Android / iOS.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      // Also ensure Android 13+ runtime permission prompt was triggered
      await NotificationService.instance.requestPermissions();

      return granted;
    } catch (e) {
      debugPrint('[Push] Error requesting notification permission: $e');
      return false;
    }
  }

  /// Check whether OS-level notification permission is currently granted.
  Future<bool> checkPermissionGranted() async {
    if (kIsWeb) return false;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// Synchronize the device registration in Supabase `user_devices`.
  Future<void> syncDeviceRegistration({
    required SupabaseClient supabaseClient,
    required String userId,
    required bool notificationsEnabled,
    required bool isDiscreet,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) {
      await initialize();
    }

    _registeredUserId = userId;

    try {
      _currentFcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] Current token: ${maskToken(_currentFcmToken)}');

      if (_currentFcmToken == null || _currentFcmToken!.isEmpty) {
        debugPrint('[PushRegistry] No FCM token available to register.');
        return;
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final deviceData = {
        'user_id': userId,
        'installation_id': _installationId,
        'fcm_token': _currentFcmToken,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'device_model': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'app_version': '1.0.4',
        'notifications_enabled': notificationsEnabled,
        'discreet': isDiscreet,
        'last_seen_at': nowIso,
        'last_token_refresh_at': nowIso,
        'updated_at': nowIso,
      };

      await supabaseClient
          .from(SupabaseConstants.userDevicesTable)
          .upsert(deviceData, onConflict: 'user_id,installation_id');

      _lastSyncTime = DateTime.now().toUtc();
      debugPrint(
        '[PushRegistry] Device registered in user_devices (user: $userId, token: ${maskToken(_currentFcmToken)})',
      );

      // Listen for token refresh and sync immediately
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
        newToken,
      ) async {
        debugPrint('[FCM] Token refreshed: ${maskToken(newToken)}');
        _currentFcmToken = newToken;
        try {
          await supabaseClient.from(SupabaseConstants.userDevicesTable).upsert({
            'user_id': userId,
            'installation_id': _installationId,
            'fcm_token': newToken,
            'platform': defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
            'notifications_enabled': notificationsEnabled,
            'discreet': isDiscreet,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
            'last_token_refresh_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id,installation_id');
          _lastSyncTime = DateTime.now().toUtc();
          debugPrint('[PushRegistry] Refreshed token synced to Supabase.');
        } catch (e) {
          debugPrint('[PushRegistry] Error syncing refreshed token: $e');
        }
      });
    } catch (e) {
      debugPrint('[PushRegistry] Failed to sync device registration: $e');
    }
  }

  /// Deactivates the current installation on logout so this device stops receiving pushes.
  Future<void> deactivateDevice(
    SupabaseClient supabaseClient,
    String userId,
  ) async {
    if (kIsWeb || _installationId == null) return;
    try {
      debugPrint(
        '[PushRegistry] Deactivating device on logout (user: $userId)',
      );
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      _registeredUserId = null;

      await supabaseClient
          .from(SupabaseConstants.userDevicesTable)
          .update({
            'notifications_enabled': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .match({'user_id': userId, 'installation_id': _installationId!});

      // Clear any active local notifications
      await NotificationService.instance.cancelAll();
    } catch (e) {
      debugPrint('[PushRegistry] Error deactivating device: $e');
    }
  }

  /// Handles incoming FCM messages while the app is in the FOREGROUND.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
      '[FCM] Foreground message received: ${message.messageId} '
      '(conv: ${message.data['conversation_id']})',
    );

    final data = message.data;
    final conversationId = data['conversation_id'] as String?;
    if (conversationId == null || conversationId.isEmpty) return;

    // 1. Active Chat Suppression: If user is actively reading this conversation, DO NOT notify
    if (activeConversationChecker != null &&
        activeConversationChecker!(conversationId)) {
      debugPrint(
        '[Push] Notification suppressed: User actively viewing conversation $conversationId',
      );
      return;
    }

    // 2. Otherwise create a local notification for the user
    final title = message.notification?.title ?? 'AnonApp';
    final body = message.notification?.body ?? 'New message received';
    final senderUsername = data['sender_username'] as String?;

    unawaited(
      NotificationService.instance.showMessageNotification(
        id: NotificationService.conversationNotificationId(conversationId),
        title: title,
        body: body,
        conversationId: conversationId,
        senderUsername: senderUsername,
      ),
    );
  }

  /// Handles user tapping an FCM notification (both background and cold-start).
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final conversationId = data['conversation_id'] as String?;
    final username = data['sender_username'] as String? ?? '';

    if (conversationId == null || conversationId.isEmpty) return;

    final encodedUsername = Uri.encodeComponent(username);
    final targetPath = '/chat/$conversationId?username=$encodedUsername';

    debugPrint('[Push] Notification tapped. Navigating to: $targetPath');
    _navigateToTarget(targetPath);
  }

  /// Navigates to target conversation path or queues it until the Navigator is ready.
  void _navigateToTarget(String targetPath) {
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        context.push(targetPath);
        _pendingNavigationPath = null;
      } catch (_) {
        _queueNavigation(targetPath);
      }
    } else {
      _queueNavigation(targetPath);
    }
  }

  void _queueNavigation(String targetPath) {
    _pendingNavigationPath = targetPath;
    // Retry periodically up to 5 times until context mounts
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      attempts++;
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        timer.cancel();
        if (_pendingNavigationPath != null) {
          ctx.push(_pendingNavigationPath!);
          _pendingNavigationPath = null;
        }
      } else if (attempts >= 10) {
        timer.cancel();
      }
    });
  }

  /// Get diagnostics status model.
  Future<PushNotificationStatus> getStatus(bool appPreferenceEnabled) async {
    final osGranted = await checkPermissionGranted();
    return PushNotificationStatus(
      appPreferenceEnabled: appPreferenceEnabled,
      osPermissionGranted: osGranted,
      fcmTokenAvailable:
          _currentFcmToken != null && _currentFcmToken!.isNotEmpty,
      isSynced: _lastSyncTime != null,
      maskedToken: maskToken(_currentFcmToken),
      lastSyncTime: _lastSyncTime,
    );
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
  }
}
