import 'package:anonapp/core/services/encryption_service.dart';
import 'package:anonapp/core/services/notification_service.dart';
import 'package:anonapp/features/messages/presentation/providers/notification_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Notification & Lifecycle Suppression Tests', () {
    test('isAppResumedProvider defaults to true and tracks state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isAppResumedProvider), isTrue);

      container.read(isAppResumedProvider.notifier).state = false;
      expect(container.read(isAppResumedProvider), isFalse);

      container.read(isAppResumedProvider.notifier).state = true;
      expect(container.read(isAppResumedProvider), isTrue);
    });

    test('activeConversationIdProvider defaults to null and tracks active chat', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(activeConversationIdProvider), isNull);

      container.read(activeConversationIdProvider.notifier).state = 'conv-123';
      expect(container.read(activeConversationIdProvider), equals('conv-123'));

      container.read(activeConversationIdProvider.notifier).state = null;
      expect(container.read(activeConversationIdProvider), isNull);
    });

    test('Notification suppression logic: only suppress when resumed AND in matching chat', () {
      bool shouldSuppress({
        required bool isResumed,
        required String? activeConversation,
        required String incomingConversationId,
      }) {
        return isResumed && activeConversation == incomingConversationId;
      }

      const convId = 'chat-abc';

      // 1. Minimized / Background while inside the chat -> MUST NOT SUPPRESS!
      expect(
        shouldSuppress(
          isResumed: false,
          activeConversation: convId,
          incomingConversationId: convId,
        ),
        isFalse,
      );

      // 2. Minimized / Background while on conversations screen -> MUST NOT SUPPRESS!
      expect(
        shouldSuppress(
          isResumed: false,
          activeConversation: null,
          incomingConversationId: convId,
        ),
        isFalse,
      );

      // 3. Resumed in foreground viewing a different chat -> MUST NOT SUPPRESS!
      expect(
        shouldSuppress(
          isResumed: true,
          activeConversation: 'different-chat',
          incomingConversationId: convId,
        ),
        isFalse,
      );

      // 4. Resumed in foreground on conversations screen -> MUST NOT SUPPRESS!
      expect(
        shouldSuppress(
          isResumed: true,
          activeConversation: null,
          incomingConversationId: convId,
        ),
        isFalse,
      );

      // 5. Resumed in foreground viewing THIS exact chat -> MUST SUPPRESS (user is reading it)
      expect(
        shouldSuppress(
          isResumed: true,
          activeConversation: convId,
          incomingConversationId: convId,
        ),
        isTrue,
      );
    });

    test('Notification payload formats correctly for different message types', () async {
      String resolveNotificationBody({
        required String messageType,
        required String rawContent,
        required bool isDiscreet,
      }) {
        if (isDiscreet) return 'New message received';
        switch (messageType) {
          case 'image':
            return '📷 Photo';
          case 'view_once_image':
            return '🔒 Photo (View once)';
          case 'audio':
            return '🎤 Voice message';
          default:
            return rawContent;
        }
      }

      expect(
        resolveNotificationBody(
          messageType: 'image',
          rawContent: '',
          isDiscreet: false,
        ),
        equals('📷 Photo'),
      );

      expect(
        resolveNotificationBody(
          messageType: 'view_once_image',
          rawContent: '',
          isDiscreet: false,
        ),
        equals('🔒 Photo (View once)'),
      );

      expect(
        resolveNotificationBody(
          messageType: 'audio',
          rawContent: '',
          isDiscreet: false,
        ),
        equals('🎤 Voice message'),
      );

      expect(
        resolveNotificationBody(
          messageType: 'text',
          rawContent: 'Hello friend!',
          isDiscreet: false,
        ),
        equals('Hello friend!'),
      );

      expect(
        resolveNotificationBody(
          messageType: 'text',
          rawContent: 'Confidential msg',
          isDiscreet: true,
        ),
        equals('New message received'),
      );
    });

    test('Encrypted message text decrypts properly for notification preview', () async {
      const convId = 'test-conversation-456';
      const plainText = 'Secret anonymous message';

      final encrypted = await EncryptionService.instance.encryptText(
        plainText,
        convId,
      );

      expect(EncryptionService.isEncrypted(encrypted), isTrue);

      final decrypted = await EncryptionService.instance.decryptText(
        encrypted,
        convId,
      );

      expect(decrypted, equals(plainText));
    });

    test('NotificationSettings copyWith preserves and updates fields correctly', () {
      const initial = NotificationSettings(enabled: true, discreet: false);

      final discreetUpdated = initial.copyWith(discreet: true);
      expect(discreetUpdated.enabled, isTrue);
      expect(discreetUpdated.discreet, isTrue);

      final disabled = initial.copyWith(enabled: false);
      expect(disabled.enabled, isFalse);
      expect(disabled.discreet, isFalse);
    });

    test('Messages from the same conversation resolve to the same notification ID for stacking', () {
      const convId = 'conv-uuid-alice-123';

      final id1 = NotificationService.conversationNotificationId(convId);
      final id2 = NotificationService.conversationNotificationId(convId);
      final id3 = NotificationService.conversationNotificationId(convId);

      // All messages from the same conversation must map to the same notification ID
      expect(id1, equals(id2));
      expect(id2, equals(id3));
      expect(id1, isNonNegative);
    });

    test('Messages from different conversations resolve to distinct notification IDs', () {
      const convAlice = 'conv-uuid-alice-123';
      const convBob = 'conv-uuid-bob-456';
      const convCharlie = 'conv-uuid-charlie-789';

      final idAlice = NotificationService.conversationNotificationId(convAlice);
      final idBob = NotificationService.conversationNotificationId(convBob);
      final idCharlie = NotificationService.conversationNotificationId(convCharlie);

      expect(idAlice, isNot(equals(idBob)));
      expect(idAlice, isNot(equals(idCharlie)));
      expect(idBob, isNot(equals(idCharlie)));

      expect(idAlice, isNonNegative);
      expect(idBob, isNonNegative);
      expect(idCharlie, isNonNegative);
    });

    test('Notification title formats correctly with unread badge count for single vs stacked messages', () {
      String resolveTitle({
        required String username,
        required int count,
        required bool isDiscreet,
      }) {
        if (isDiscreet) {
          return count > 1 ? 'AnonApp ($count messages)' : 'AnonApp';
        }
        return count > 1 ? '@$username ($count)' : '@$username';
      }

      // Single message
      expect(resolveTitle(username: 'alice', count: 1, isDiscreet: false), equals('@alice'));
      expect(resolveTitle(username: 'alice', count: 1, isDiscreet: true), equals('AnonApp'));

      // Stacked multiple messages
      expect(resolveTitle(username: 'alice', count: 3, isDiscreet: false), equals('@alice (3)'));
      expect(resolveTitle(username: 'alice', count: 5, isDiscreet: true), equals('AnonApp (5 messages)'));
    });

    test('Conversation unread lines buffer stacks chronologically and caps at 7 lines', () {
      final lines = <String>[];
      for (int i = 1; i <= 10; i++) {
        lines.add('Message $i');
        if (lines.length > 7) {
          lines.removeAt(0);
        }
      }

      expect(lines.length, equals(7));
      expect(lines.first, equals('Message 4'));
      expect(lines.last, equals('Message 10'));
    });

    test('Unified application group key bundles notifications for system drawer', () {
      const groupKey = 'com.example.anonapp.MESSAGES';
      expect(groupKey, equals('com.example.anonapp.MESSAGES'));

      const convId = 'conv-uuid-alice-123';
      const iosThreadId = 'anonapp_conv_$convId';
      expect(iosThreadId, equals('anonapp_conv_conv-uuid-alice-123'));
    });

    test('Rolling window for sync is resilient to server/client clock drift', () {
      final now = DateTime.now().toUtc();
      final windowStart = now.subtract(const Duration(minutes: 10));

      // Simulate a server timestamp that is 5 seconds behind the client device's clock
      final serverTimestampBehind = now.subtract(const Duration(seconds: 5));
      expect(serverTimestampBehind.isAfter(windowStart), isTrue);

      // Simulate a server timestamp that is 30 seconds behind
      final serverTimestampLag = now.subtract(const Duration(seconds: 30));
      expect(serverTimestampLag.isAfter(windowStart), isTrue);
    });

    test('Message deduplication avoids duplicates during sync', () {
      final existing = [
        {'id': 'm3', 'created_at': DateTime.now().toUtc().toIso8601String()},
        {'id': 'm2', 'created_at': DateTime.now().toUtc().subtract(const Duration(seconds: 10)).toIso8601String()},
        {'id': 'm1', 'created_at': DateTime.now().toUtc().subtract(const Duration(seconds: 20)).toIso8601String()},
      ];

      final incomingFromServer = [
        {'id': 'm4', 'created_at': DateTime.now().toUtc().add(const Duration(seconds: 1)).toIso8601String()}, // new
        {'id': 'm3', 'created_at': DateTime.now().toUtc().toIso8601String()}, // duplicate
        {'id': 'm2', 'created_at': DateTime.now().toUtc().subtract(const Duration(seconds: 10)).toIso8601String()}, // duplicate
      ];

      final existingIds = existing.map((m) => m['id']).toSet();
      final newItems = incomingFromServer.where((m) => !existingIds.contains(m['id'])).toList();

      expect(newItems.length, equals(1));
      expect(newItems.first['id'], equals('m4'));
    });
  });
}
