import 'dart:async';

import 'package:anonapp/core/services/presence/presence_provider.dart';
import 'package:anonapp/core/services/presence/presence_service.dart';
import 'package:anonapp/core/theme/app_colors.dart';
import 'package:anonapp/features/conversations/domain/models/conversation.dart';
import 'package:anonapp/features/conversations/presentation/providers/conversation_provider.dart';
import 'package:anonapp/features/conversations/presentation/screens/conversations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake PresenceService for unit and widget testing.
class FakePresenceService implements PresenceService {
  final _controller = StreamController<Set<String>>.broadcast();
  Set<String> _online = <String>{};
  bool _isTracking = false;
  int setOnlineCallCount = 0;
  int setOfflineCallCount = 0;

  @override
  Set<String> get currentOnlineUsers => Set.unmodifiable(_online);

  @override
  Stream<Set<String>> get onlineUsersStream => _controller.stream;

  @override
  bool get isTracking => _isTracking;

  void emitOnlineUsers(Set<String> users) {
    _online = users;
    _controller.add(users);
  }

  @override
  Future<void> initialize({
    required String userId,
    required bool canShowOnline,
  }) async {
    if (canShowOnline) {
      await setOnline();
    }
  }

  @override
  Future<void> setOnline() async {
    setOnlineCallCount++;
    _isTracking = true;
  }

  @override
  Future<void> setOffline() async {
    setOfflineCallCount++;
    _isTracking = false;
  }

  @override
  Future<void> updatePrivacySetting(bool canShowOnline) async {
    if (!canShowOnline) {
      await setOffline();
    } else {
      await setOnline();
    }
  }

  int reconnectNowCallCount = 0;

  @override
  Future<void> reconnectNow() async {
    reconnectNowCallCount++;
  }

  @override
  Future<void> disposeChannelOnly() async {
    _isTracking = false;
    _online = <String>{};
    _controller.add(_online);
  }

  @override
  Future<void> dispose() async {
    await disposeChannelOnly();
    await _controller.close();
  }
}

void main() {
  group('Presence & Lifecycle State Tests', () {
    test('isUserOnlineProvider returns true only when userId is in online set', () async {
      final fakeService = FakePresenceService();
      final container = ProviderContainer(
        overrides: [
          presenceServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      // Initially empty
      expect(container.read(isUserOnlineProvider('alice')), isFalse);
      expect(container.read(isUserOnlineProvider('bob')), isFalse);
      expect(container.read(isUserOnlineProvider(null)), isFalse);
      expect(container.read(isUserOnlineProvider('')), isFalse);

      // Alice comes online
      fakeService.emitOnlineUsers({'alice'});
      await pumpEventQueue();
      expect(container.read(isUserOnlineProvider('alice')), isTrue);
      expect(container.read(isUserOnlineProvider('bob')), isFalse);

      // Bob also comes online
      fakeService.emitOnlineUsers({'alice', 'bob'});
      await pumpEventQueue();
      expect(container.read(isUserOnlineProvider('alice')), isTrue);
      expect(container.read(isUserOnlineProvider('bob')), isTrue);

      // Alice goes offline (minimizes, closes app, switches tab, locks screen)
      fakeService.emitOnlineUsers({'bob'});
      await pumpEventQueue();
      expect(container.read(isUserOnlineProvider('alice')), isFalse);
      expect(container.read(isUserOnlineProvider('bob')), isTrue);
    });

    test('Lifecycle state changes correctly trigger online vs offline', () {
      final fakeService = FakePresenceService();

      void simulateLifecycleChange(AppLifecycleState state) {
        if (state == AppLifecycleState.resumed) {
          fakeService.setOnline();
        } else {
          fakeService.setOffline();
        }
      }

      // App starts / resumes in foreground
      simulateLifecycleChange(AppLifecycleState.resumed);
      expect(fakeService.isTracking, isTrue);
      expect(fakeService.setOnlineCallCount, equals(1));

      // 1. User locks screen or opens app switcher -> inactive
      simulateLifecycleChange(AppLifecycleState.inactive);
      expect(fakeService.isTracking, isFalse);
      expect(fakeService.setOfflineCallCount, equals(1));

      // 2. User minimizes app -> paused
      simulateLifecycleChange(AppLifecycleState.paused);
      expect(fakeService.isTracking, isFalse);
      expect(fakeService.setOfflineCallCount, equals(2));

      // 3. App is hidden -> hidden
      simulateLifecycleChange(AppLifecycleState.hidden);
      expect(fakeService.isTracking, isFalse);
      expect(fakeService.setOfflineCallCount, equals(3));

      // 4. App is closing -> detached
      simulateLifecycleChange(AppLifecycleState.detached);
      expect(fakeService.isTracking, isFalse);
      expect(fakeService.setOfflineCallCount, equals(4));

      // 5. User unlocks screen or opens app back -> resumed
      simulateLifecycleChange(AppLifecycleState.resumed);
      expect(fakeService.isTracking, isTrue);
      expect(fakeService.setOnlineCallCount, equals(2));
    });

    test('PresenceSyncManager debounces offline transitions during brief inactive states', () async {
      final fakeService = FakePresenceService();

      final manager = PresenceSyncManager(
        fakeService,
        debounceDuration: const Duration(milliseconds: 50),
      );
      addTearDown(manager.dispose);

      // App starts online
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(fakeService.setOnlineCallCount, equals(1));
      expect(fakeService.setOfflineCallCount, equals(0));

      // User pulls down notification shade (inactive)
      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      // Immediately, offline should NOT have been called yet because of the grace period
      expect(fakeService.setOfflineCallCount, equals(0));

      // User puts away notification shade quickly (resumed within 10ms < 50ms grace)
      await Future<void>.delayed(const Duration(milliseconds: 10));
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Wait past the original 50ms window
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Offline call was suppressed!
      expect(fakeService.setOfflineCallCount, equals(0));
      expect(fakeService.setOnlineCallCount, equals(2));
    });

    test('PresenceSyncManager triggers setOffline after debounce duration expires', () async {
      final fakeService = FakePresenceService();

      final manager = PresenceSyncManager(
        fakeService,
        debounceDuration: const Duration(milliseconds: 40),
      );
      addTearDown(manager.dispose);

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(fakeService.setOnlineCallCount, equals(1));

      // App minimized (paused)
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(fakeService.setOfflineCallCount, equals(0));

      // Wait past debounce timer
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fakeService.setOfflineCallCount, equals(1));
    });

    test('PresenceSyncManager immediately calls setOffline on detached without debounce', () {
      final fakeService = FakePresenceService();

      final manager = PresenceSyncManager(
        fakeService,
        debounceDuration: const Duration(seconds: 10),
      );
      addTearDown(manager.dispose);

      manager.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(fakeService.setOfflineCallCount, equals(1));
    });

    test('Strict presence: isUserOnlineProvider relies strictly on Realtime presence', () async {
      final fakeService = FakePresenceService();
      final container = ProviderContainer(
        overrides: [
          presenceServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      // User 'charlie' is NOT in WebSocket presence
      expect(container.read(isUserOnlineProvider('charlie')), isFalse);

      // Even if activity was recorded 30 seconds ago, user is offline if not in presence
      container.read(userLastSeenProvider.notifier).recordLastSeen(
        'charlie',
        DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
      );

      // Offline because WebSocket presence is the single source of truth
      expect(container.read(isUserOnlineProvider('charlie')), isFalse);

      // When added to presence, user is online
      fakeService.emitOnlineUsers({'charlie'});
      await pumpEventQueue();
      expect(container.read(isUserOnlineProvider('charlie')), isTrue);
    });

    test('Privacy setting toggle immediately sets user offline when disabled', () async {
      final fakeService = FakePresenceService();

      await fakeService.initialize(userId: 'my-user-id', canShowOnline: true);
      expect(fakeService.isTracking, isTrue);

      // User toggles "Show Online Status" OFF
      await fakeService.updatePrivacySetting(false);
      expect(fakeService.isTracking, isFalse);
      expect(fakeService.setOfflineCallCount, equals(1));

      // User toggles "Show Online Status" back ON
      await fakeService.updatePrivacySetting(true);
      expect(fakeService.isTracking, isTrue);
      expect(fakeService.setOnlineCallCount, equals(2));
    });
  });

  group('ConversationTile UI Online/Offline Indicator Tests', () {
    testWidgets('Renders glowing green dot when other member is online', (tester) async {
      final fakeService = FakePresenceService();
      fakeService.emitOnlineUsers({'user-other'});

      final testConversation = Conversation(
        id: 'conv-1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherMemberId: 'user-other',
        otherMemberUsername: 'alice',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            presenceServiceProvider.overrideWithValue(fakeService),
            conversationsProvider.overrideWith((ref) async => [testConversation]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ConversationsScreen(onNavigateToSearch: () {}),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final onlineDot = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.color == AppColors.online;
        }
        return false;
      });
      expect(onlineDot, findsOneWidget);
    });

    testWidgets('Renders offline grey dot when other member is offline', (tester) async {
      final fakeService = FakePresenceService();
      // 'user-other' is NOT in the online set

      final testConversation = Conversation(
        id: 'conv-1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherMemberId: 'user-other',
        otherMemberUsername: 'alice',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            presenceServiceProvider.overrideWithValue(fakeService),
            conversationsProvider.overrideWith((ref) async => [testConversation]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ConversationsScreen(onNavigateToSearch: () {}),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final offlineDot = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.color == AppColors.offline;
        }
        return false;
      });
      expect(offlineDot, findsOneWidget);
    });
  });
}
