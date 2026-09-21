import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/supabase_constants.dart';
import 'presence_web_stub.dart'
    if (dart.library.js_interop) 'presence_web.dart' as platform;

/// Service managing real-time user presence (online/offline status) across
/// mobile, desktop, and web platforms with auto-reconnection resilience.
class PresenceService {
  PresenceService(this._client);

  final SupabaseClient _client;

  RealtimeChannel? _channel;
  String? _userId;
  bool _canShowOnline = true;
  bool _isTracking = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  StreamSubscription<dynamic>? _webSubscription;

  final _onlineUsersController = StreamController<Set<String>>.broadcast();
  Set<String> _currentOnlineUsers = <String>{};

  /// The current snapshot of all online user IDs.
  Set<String> get currentOnlineUsers => Set.unmodifiable(_currentOnlineUsers);

  /// Stream of online user IDs updated on real-time sync/join/leave events.
  Stream<Set<String>> get onlineUsersStream => _onlineUsersController.stream;

  /// Whether this client is currently tracking as online.
  bool get isTracking => _isTracking;

  /// Initialize presence channel subscription for the authenticated user.
  Future<void> initialize({
    required String userId,
    required bool canShowOnline,
  }) async {
    if (_userId == userId && _channel != null) {
      if (_canShowOnline != canShowOnline) {
        await updatePrivacySetting(canShowOnline);
      }
      return;
    }

    _userId = userId;
    _canShowOnline = canShowOnline;

    await _setupChannel(userId, canShowOnline);

    // Attach web-specific visibility and lifecycle listeners
    if (kIsWeb) {
      await _webSubscription?.cancel();
      _webSubscription = platform.initWebPresenceListeners(
        onHide: () => unawaited(setOffline()),
        onShow: () {
          if (_canShowOnline) unawaited(setOnline());
        },
      );
    }
  }

  /// Sets up or tears down & rebinds the Realtime presence channel.
  Future<void> _setupChannel(String userId, bool canShowOnline) async {
    // Tear down any existing channel instance first
    if (_channel != null) {
      try {
        if (_isTracking) {
          await _channel?.untrack();
        }
        await _channel?.unsubscribe();
        await _client.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }

    final channel = _client.channel(
      SupabaseConstants.presenceChannel,
      opts: RealtimeChannelConfig(key: userId),
    );

    channel
        .onPresenceSync((_) {
          _syncPresence();
        })
        .onPresenceJoin((_) {
          _syncPresence();
        })
        .onPresenceLeave((_) {
          _syncPresence();
        });

    _channel = channel;

    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _syncPresence();
        if (_canShowOnline && !platform.isWebDocumentHidden()) {
          unawaited(setOnline());
        }
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        debugPrint(
          '[PresenceService] Realtime channel status: $status ($error). Scheduling reconnect.',
        );
        _scheduleReconnect();
      }
    });
  }

  /// Reconnect immediately if channel is dead or disconnected (e.g. on app resume).
  Future<void> reconnectNow() async {
    final uid = _userId;
    if (uid == null || !_canShowOnline) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    debugPrint('[PresenceService] Immediate channel reconnect requested.');
    await _setupChannel(uid, _canShowOnline);
  }

  /// Schedules an auto-reconnection attempt with exponential backoff.
  void _scheduleReconnect({bool immediate = false}) {
    if (_reconnectTimer?.isActive ?? false) return;
    final uid = _userId;
    if (uid == null || !_canShowOnline) return;

    if (immediate) {
      _reconnectAttempts = 0;
      unawaited(_setupChannel(uid, _canShowOnline));
      return;
    }

    _reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s (capped at 16s)
    final delaySeconds = (1 << (_reconnectAttempts.clamp(1, 4))) ~/ 2;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (_userId != null && _canShowOnline) {
        debugPrint(
          '[PresenceService] Attempting channel re-subscription (attempt $_reconnectAttempts)...',
        );
        await _setupChannel(_userId!, _canShowOnline);
      }
    });
  }

  /// Mark the current user as ONLINE.
  Future<void> setOnline() async {
    final uid = _userId;
    if (uid == null || !_canShowOnline || platform.isWebDocumentHidden()) return;

    // Check if channel is null or socket disconnected; re-establish if needed
    if (_channel == null || !_client.realtime.isConnected) {
      debugPrint('[PresenceService] Socket or channel inactive in setOnline. Re-establishing channel...');
      await _setupChannel(uid, _canShowOnline);
      return;
    }

    _isTracking = true;
    try {
      final response = await _channel?.track({
        'user_id': uid,
        'online_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (response != null && response != ChannelResponse.ok) {
        debugPrint('[PresenceService] track() returned status: $response');
        if (response == ChannelResponse.timedOut) {
          _scheduleReconnect();
        }
      }
      _syncPresence();
    } catch (e) {
      debugPrint('[PresenceService] Error tracking presence online: $e');
    }

    // Refresh last_seen in DB
    try {
      await _client
          .from(SupabaseConstants.profilesTable)
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid);
    } catch (_) {}

    // Reset heartbeat timer to periodically refresh presence lease
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AppConstants.presenceHeartbeat, (_) async {
      if (_isTracking &&
          _userId != null &&
          _canShowOnline &&
          !platform.isWebDocumentHidden()) {
        try {
          final status = await _channel?.track({
            'user_id': _userId!,
            'online_at': DateTime.now().toUtc().toIso8601String(),
          });
          if (status == ChannelResponse.timedOut) {
            _scheduleReconnect();
          }
        } catch (_) {}
      }
    });
  }

  /// Mark the current user as OFFLINE.
  /// Triggered on app minimization, tab switch, window blur, screen lock, or app close.
  Future<void> setOffline() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (!_isTracking) return;
    _isTracking = false;

    try {
      await _channel?.untrack();
    } catch (e) {
      debugPrint('[PresenceService] Error untracking presence offline: $e');
    }

    _syncPresence();

    // Update last_seen in DB if online visibility is enabled
    final uid = _userId;
    if (uid != null && _canShowOnline) {
      try {
        await _client
            .from(SupabaseConstants.profilesTable)
            .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
            .eq('id', uid);
      } catch (_) {}
    }
  }

  /// Update the user's online visibility privacy preference.
  Future<void> updatePrivacySetting(bool canShowOnline) async {
    _canShowOnline = canShowOnline;
    if (!canShowOnline) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      await setOffline();
    } else if (!platform.isWebDocumentHidden()) {
      await setOnline();
    }
  }

  /// Extract active online user IDs from Realtime presence state.
  void _syncPresence() {
    final channel = _channel;
    if (channel == null) return;

    try {
      final states = channel.presenceState();
      final newSet = <String>{};

      for (final state in states) {
        if (state.presences.isNotEmpty) {
          for (final p in state.presences) {
            final uid = p.payload['user_id'] as String? ?? state.key;
            if (uid.isNotEmpty) {
              newSet.add(uid);
            }
          }
        }
      }

      _currentOnlineUsers = newSet;
      if (!_onlineUsersController.isClosed) {
        _onlineUsersController.add(newSet);
      }
    } catch (e) {
      debugPrint('[PresenceService] Error reading presence state: $e');
    }
  }

  /// Disposes only the channel and heartbeat, keeping the stream controller alive.
  Future<void> disposeChannelOnly() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _webSubscription?.cancel();
    _webSubscription = null;

    if (_channel != null) {
      try {
        if (_isTracking) {
          await _channel?.untrack();
        }
        await _channel?.unsubscribe();
        await _client.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
    _isTracking = false;
    _currentOnlineUsers = <String>{};
    if (!_onlineUsersController.isClosed) {
      _onlineUsersController.add(_currentOnlineUsers);
    }
  }

  /// Full teardown of the service.
  Future<void> dispose() async {
    await disposeChannelOnly();
    await _onlineUsersController.close();
  }
}
