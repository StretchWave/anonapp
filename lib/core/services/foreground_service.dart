import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'encryption_service.dart';
import 'notification_service.dart';

/// Top-level callback entry point required by [FlutterForegroundTask].
@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(AnonAppForegroundTaskHandler());
}

/// Background task handler that runs on Android when the service is active.
/// Keeps the app process alive in the foreground (`adj <= 200`), holds partial wake-lock,
/// and verifies incoming messages periodically to guarantee system notifications.
class AnonAppForegroundTaskHandler extends TaskHandler {
  final Set<String> _notifiedMessageIds = {};
  final Map<String, String> _usernameCache = {};
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

    // 2. Perform standalone REST sync check only if main isolate is suspended or inactive (> 10s)
    final now = DateTime.now();
    final isMainActive =
        _lastMainPing != null && now.difference(_lastMainPing!).inSeconds < 10;

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

  Future<String?> _getSenderUsername(
    HttpClient client,
    String supabaseUrl,
    String anonKey,
    String? token,
    String senderId,
  ) async {
    if (_usernameCache.containsKey(senderId)) {
      return _usernameCache[senderId];
    }
    try {
      final queryUri = Uri.parse(
        '$supabaseUrl/rest/v1/profiles?id=eq.$senderId&select=username',
      );
      final req = await client.getUrl(queryUri);
      req.headers.set('apikey', anonKey);
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List<dynamic>;
        if (list.isNotEmpty &&
            list.first is Map &&
            list.first['username'] != null) {
          final username = list.first['username'] as String;
          _usernameCache[senderId] = username;
          return username;
        }
      }
    } catch (_) {}
    return null;
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
      final windowStart = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();

      final queryUri = Uri.parse(
        '$supabaseUrl/rest/v1/messages'
        '?select=id,conversation_id,sender_id,content,message_type,created_at,deleted_at,expires_at'
        '&sender_id=neq.$userId'
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
          if (item['deleted_at'] != null) continue;

          final expiresAtStr = item['expires_at'] as String?;
          if (expiresAtStr != null) {
            final exp = DateTime.tryParse(expiresAtStr)?.toUtc();
            if (exp != null && DateTime.now().toUtc().isAfter(exp)) {
              continue;
            }
          }

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
            case 'document':
              preview = '📎 Document';
              break;
            default:
              final rawContent = item['content'] as String? ?? '';
              if (EncryptionService.isEncrypted(rawContent)) {
                preview = await EncryptionService.instance.decryptText(
                  rawContent,
                  convId,
                );
              } else if (rawContent.isNotEmpty) {
                preview = rawContent;
              } else {
                preview = 'New message';
              }
              break;
          }

          final senderId = item['sender_id'] as String?;
          final senderUsername = senderId != null
              ? await _getSenderUsername(
                  client,
                  supabaseUrl,
                  anonKey,
                  token,
                  senderId,
                )
              : null;

          final notifId =
              NotificationService.conversationNotificationId(convId);
          await NotificationService.instance.showMessageNotification(
            id: notifId,
            title: senderUsername != null ? '@$senderUsername' : 'AnonApp',
            body: preview,
            conversationId: convId,
            senderUsername: senderUsername,
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
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _initialized = true;
  }

  /// Starts the foreground service if not already running.
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

    await FlutterForegroundTask.saveData(key: 'user_id', value: userId);
    await FlutterForegroundTask.saveData(key: 'supabase_url', value: supabaseUrl);
    await FlutterForegroundTask.saveData(key: 'supabase_anon_key', value: supabaseAnonKey);
    if (authToken != null) {
      await FlutterForegroundTask.saveData(key: 'auth_token', value: authToken);
    }

    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (!isRunning) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          serviceTypes: [
            ForegroundServiceTypes.dataSync,
            ForegroundServiceTypes.remoteMessaging,
          ],
          notificationTitle: 'AnonApp',
          notificationText: 'Encrypted chat active',
          callback: startForegroundTaskCallback,
        );
        debugPrint('[ForegroundService] Foreground service started successfully');
      }
    } catch (e) {
      debugPrint('[ForegroundService] Start service error: $e');
    }
  }

  /// Stops the foreground service.
  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        await FlutterForegroundTask.stopService();
        debugPrint('[ForegroundService] Foreground service stopped');
      }
    } catch (e) {
      debugPrint('[ForegroundService] Stop service error: $e');
    }
  }

  /// Request battery optimization exemption so Android OS does not kill background sync.
  Future<void> requestBatteryExemption() async {
    if (kIsWeb) return;
    try {
      final isIgnoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      debugPrint('[ForegroundService] Battery optimization request error: $e');
    }
  }

  /// Sends heartbeat ping to background task isolate.
  void pingBackground() {
    if (kIsWeb) return;
    try {
      FlutterForegroundTask.sendDataToTask({'status': 'main_active'});
    } catch (_) {}
  }

  /// Adds a callback to receive data sent from the TaskHandler.
  void addTaskDataCallback(ValueChanged<Object> callback) {
    if (kIsWeb) return;
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  /// Removes a callback to receive data sent from the TaskHandler.
  void removeTaskDataCallback(ValueChanged<Object> callback) {
    if (kIsWeb) return;
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }

  /// Minimizes the application to the background without destroying it.
  void minimizeApp() {
    if (kIsWeb) return;
    FlutterForegroundTask.minimizeApp();
  }
}
