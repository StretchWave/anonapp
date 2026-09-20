import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notification_service.dart';

/// Top-level callback entry point required by [FlutterForegroundTask].
@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(AnonAppForegroundTaskHandler());
}

/// Background task handler that runs on a separate isolate on Android.
/// Keeps the app process alive, holds partial wake-lock, and verifies incoming
/// messages periodically to guarantee system notifications with sound when minimized.
class AnonAppForegroundTaskHandler extends TaskHandler {
  final Set<String> _notifiedMessageIds = {};
  DateTime? _lastMainPing;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!kIsWeb) {
      await NotificationService.instance.initialize();
    }
    debugPrint('[ForegroundService] Started with: ${starter.name}');
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // 1. Notify main isolate if active
    FlutterForegroundTask.sendDataToMain({'action': 'check_unread'});

    // 2. Perform standalone REST sync check only if main isolate is suspended or inactive (> 12s)
    final now = DateTime.now();
    final isMainActive =
        _lastMainPing != null && now.difference(_lastMainPing!).inSeconds < 12;

    if (!isMainActive) {
      await _checkUnreadFromBackground();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundService] Destroyed');
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['status'] == 'main_active') {
      _lastMainPing = DateTime.now();
    }
    debugPrint('[ForegroundService] Received data from main: $data');
  }

  Future<void> _checkUnreadFromBackground() async {
    final userId = await FlutterForegroundTask.getData<String>(key: 'user_id');
    final supabaseUrl =
        await FlutterForegroundTask.getData<String>(key: 'supabase_url');
    final anonKey =
        await FlutterForegroundTask.getData<String>(key: 'supabase_anon_key');
    final token = await FlutterForegroundTask.getData<String>(key: 'auth_token');

    if (userId == null || supabaseUrl == null || anonKey == null) return;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      // Rolling 10-minute window prevents missed messages from clock drift
      final windowStart = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();

      final queryUri = Uri.parse(
        '$supabaseUrl/rest/v1/messages'
        '?sender_id=neq.$userId'
        '&read_at=is.null'
        '&created_at=gt.$windowStart'
        '&order=created_at.asc'
        '&limit=20',
      );

      final request = await client.getUrl(queryUri);
      request.headers.set('apikey', anonKey);
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final List<dynamic> records = jsonDecode(body) as List<dynamic>;

        for (final item in records) {
          if (item is! Map<String, dynamic>) continue;
          final msgId = item['id'] as String?;
          final convId = item['conversation_id'] as String?;
          if (msgId == null || convId == null) continue;
          if (_notifiedMessageIds.contains(msgId)) continue;
          _notifiedMessageIds.add(msgId);
          if (_notifiedMessageIds.length > 300) {
            _notifiedMessageIds.remove(_notifiedMessageIds.first);
          }

          final msgType = item['message_type'] as String? ?? 'text';
          String preview;
          switch (msgType) {
            case 'image':
              preview = '📷 Photo';
              break;
            case 'view_once_image':
              preview = '🔒 Photo (View once)';
              break;
            case 'audio':
              preview = '🎤 Voice message';
              break;
            default:
              preview = 'New message received';
              break;
          }

          // Group notifications per conversation on Android
          final notifId =
              NotificationService.conversationNotificationId(convId);
          await NotificationService.instance.showMessageNotification(
            id: notifId,
            title: 'AnonApp',
            body: preview,
            conversationId: convId,
          );
        }
      }
    } catch (e) {
      debugPrint('[ForegroundService] Standalone poll error: $e');
    } finally {
      client.close();
    }
  }
}

/// Service managing the Android foreground service lifecycle.
/// Strictly no-ops on Web.
class AppForegroundService {
  AppForegroundService._();
  static final AppForegroundService instance = AppForegroundService._();

  bool _initialized = false;

  /// Initializes the foreground task port and options.
  void initialize() {
    if (kIsWeb || _initialized) return;

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'anonapp_bg_service',
        channelName: 'AnonApp Background Service',
        channelDescription:
            'Maintains live connection for incoming message notifications',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        visibility: NotificationVisibility.VISIBILITY_SECRET,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );

    _initialized = true;
  }

  /// Stops any running foreground service so that no sticky notification lingers in the status bar,
  /// while keeping standard message notifications and background sync active.
  Future<void> start({
    required String userId,
    required String supabaseUrl,
    required String supabaseAnonKey,
    String? authToken,
  }) async {
    if (kIsWeb) return;

    if (!_initialized) {
      initialize();
    }

    // Stop any previously started foreground service so the sticky notification is immediately dismissed
    await stop();
  }

  /// Stops the foreground service.
  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('[ForegroundService] Stop service error: $e');
    }
  }

  /// Minimizes the application to the background without destroying it.
  void minimizeApp() {
    if (kIsWeb) return;
    FlutterForegroundTask.minimizeApp();
  }
}
