import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../features/conversations/domain/models/conversation.dart';
import '../../../features/conversations/presentation/providers/conversation_provider.dart';
import '../../../features/profile/data/safety_repository.dart';
import '../../../features/profile/presentation/providers/safety_provider.dart';
import '../supabase_service.dart';
import 'presence_service.dart';

/// Provides the singleton [PresenceService].
final presenceServiceProvider = Provider<PresenceService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = PresenceService(client);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Reactive set of currently online user IDs.
final onlineUserIdsProvider =
    StateNotifierProvider<OnlineUsersNotifier, Set<String>>((ref) {
      final service = ref.watch(presenceServiceProvider);
      return OnlineUsersNotifier(service);
    });

class OnlineUsersNotifier extends StateNotifier<Set<String>> {
  OnlineUsersNotifier(this._service) : super(_service.currentOnlineUsers) {
    _subscription = _service.onlineUsersStream.listen((users) {
      state = users;
    });
  }

  final PresenceService _service;
  StreamSubscription<Set<String>>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Stores the latest known activity/last-seen timestamps for users.
class UserLastSeenNotifier extends StateNotifier<Map<String, DateTime>> {
  UserLastSeenNotifier() : super(const {});

  void recordLastSeen(String userId, DateTime timestamp) {
    final existing = state[userId];
    if (existing == null || timestamp.isAfter(existing)) {
      state = {...state, userId: timestamp};
    }
  }

  void recordMultipleLastSeen(Map<String, DateTime> updates) {
    final newState = Map<String, DateTime>.from(state);
    var changed = false;
    for (final entry in updates.entries) {
      final existing = newState[entry.key];
      if (existing == null || entry.value.isAfter(existing)) {
        newState[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) {
      state = newState;
    }
  }
}

/// Reactive provider of user last seen timestamps.
final userLastSeenProvider =
    StateNotifierProvider<UserLastSeenNotifier, Map<String, DateTime>>((ref) {
      return UserLastSeenNotifier();
    });

/// Checks whether a specific user is currently verified as online.
/// Checks Realtime presence first, and falls back to a 90-second hybrid window
/// based on recent activity/last seen.
final isUserOnlineProvider = Provider.family<bool, String?>((ref, userId) {
  if (userId == null || userId.isEmpty) return false;
  final onlineIds = ref.watch(onlineUserIdsProvider);
  if (onlineIds.contains(userId)) return true;

  final lastSeenMap = ref.watch(userLastSeenProvider);
  final lastSeen = lastSeenMap[userId];
  if (lastSeen != null) {
    final diff = DateTime.now().toUtc().difference(lastSeen.toUtc());
    if (diff.inSeconds >= 0 && diff.inSeconds <= 90) {
      return true;
    }
  }
  return false;
});

/// Lifecycle and presence synchronization manager.
/// Must be watched at root (`AnonApp`) to maintain active presence monitoring.
final presenceSyncProvider = Provider<PresenceSyncManager>((ref) {
  final service = ref.watch(presenceServiceProvider);
  final manager = PresenceSyncManager(service, ref: ref);
  ref.onDispose(() {
    manager.dispose();
  });
  return manager;
});

@visibleForTesting
class PresenceSyncManager with WidgetsBindingObserver {
  PresenceSyncManager(
    this._service, {
    Ref? ref,
    this.debounceDuration = const Duration(seconds: 12),
  }) : _ref = ref { // ignore: prefer_initializing_formals
    WidgetsBinding.instance.addObserver(this);
    if (_ref != null) {
      _init();
    }
  }

  final Ref? _ref;
  final PresenceService _service;
  final Duration debounceDuration;

  ProviderSubscription<dynamic>? _authSub;
  ProviderSubscription<dynamic>? _privacySub;
  ProviderSubscription<dynamic>? _convSub;
  Timer? _debounceTimer;

  void _init() {
    final ref = _ref;
    if (ref == null) return;

    // 1. Listen for auth changes (login / logout)
    _authSub = ref.listen(authStateProvider, (prev, next) {
      _handleAuthOrPrivacyChange();
    });

    // 2. Listen for privacy settings changes (showOnlineStatus toggle)
    _privacySub = ref.listen(privacySettingsProvider, (prev, next) {
      _handleAuthOrPrivacyChange();
    });

    // 3. Seed user last-seen cache when conversations update
    _convSub = ref.listen<AsyncValue<List<Conversation>>>(
      conversationsProvider,
      (prev, next) {
        final convs = next.valueOrNull;
        if (convs != null) {
          final updates = <String, DateTime>{};
          for (final c in convs) {
            final otherId = c.otherMemberId;
            final lastSeen = c.otherMemberLastSeen ?? c.lastMessageAt;
            if (otherId != null && lastSeen != null) {
              updates[otherId] = lastSeen;
            }
          }
          if (updates.isNotEmpty) {
            ref.read(userLastSeenProvider.notifier).recordMultipleLastSeen(updates);
          }
        }
      },
    );

    // Initial trigger
    _handleAuthOrPrivacyChange();
  }

  void _handleAuthOrPrivacyChange() {
    final ref = _ref;
    if (ref == null) return;

    final client = ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser?.id;
    final privacySettings =
        ref.read(privacySettingsProvider).valueOrNull ??
        const PrivacySettings();

    if (userId != null) {
      _service.initialize(
        userId: userId,
        canShowOnline: privacySettings.showOnlineStatus,
      );
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _service.disposeChannelOnly();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // In foreground: immediately cancel pending offline transitions and mark online
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _service.setOnline();
    } else if (state == AppLifecycleState.detached) {
      // App closing / terminating: immediately mark offline
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _service.setOffline();
    } else {
      // inactive, paused, hidden:
      // Apply a grace period debounce before untracking to prevent notification
      // shade pulls, photo pickers, app switcher swipes, or brief backgroundings
      // from flashing the user offline.
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceDuration, () {
        _service.setOffline();
      });
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _authSub?.close();
    _privacySub?.close();
    _convSub?.close();
  }
}
