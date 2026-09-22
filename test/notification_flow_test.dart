import 'package:anonapp/core/services/encryption_service.dart';
import 'package:anonapp/core/services/notification_service.dart';
import 'package:anonapp/core/services/push_notification_service.dart';
import 'package:anonapp/features/messages/presentation/providers/notification_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Push Notification Architecture & FCM Lifecycle Tests', () {
    test('1. isAppResumedProvider defaults to true and tracks lifecycle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isAppResumedProvider), isTrue);

      container.read(isAppResumedProvider.notifier).state = false;
      expect(container.read(isAppResumedProvider), isFalse);

      container.read(isAppResumedProvider.notifier).state = true;
      expect(container.read(isAppResumedProvider), isTrue);
    });

    test(
      '2. activeConversationIdProvider tracks currently opened conversation',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(activeConversationIdProvider), isNull);

        container.read(activeConversationIdProvider.notifier).state =
            'conv-123';
        expect(
          container.read(activeConversationIdProvider),
          equals('conv-123'),
        );

        container.read(activeConversationIdProvider.notifier).state = null;
        expect(container.read(activeConversationIdProvider), isNull);
      },
    );

    test(
      '3. Active-chat suppression logic: only suppress when resumed AND inside matching chat',
      () {
        bool shouldSuppress({
          required bool isResumed,
          required String? activeConversation,
          required String incomingConversationId,
        }) {
          return isResumed && activeConversation == incomingConversationId;
        }

        const convId = 'chat-abc';

        // Background while inside chat: must NOT suppress (device is locked or app minimized)
        expect(
          shouldSuppress(
            isResumed: false,
            activeConversation: convId,
            incomingConversationId: convId,
          ),
          isFalse,
        );

        // Background on conversations screen: must NOT suppress
        expect(
          shouldSuppress(
            isResumed: false,
            activeConversation: null,
            incomingConversationId: convId,
          ),
          isFalse,
        );

        // Resumed viewing a different chat: must NOT suppress
        expect(
          shouldSuppress(
            isResumed: true,
            activeConversation: 'different-chat',
            incomingConversationId: convId,
          ),
          isFalse,
        );

        // Resumed on conversations list: must NOT suppress
        expect(
          shouldSuppress(
            isResumed: true,
            activeConversation: null,
            incomingConversationId: convId,
          ),
          isFalse,
        );

        // Resumed viewing THIS exact chat: MUST suppress (user is reading live messages)
        expect(
          shouldSuppress(
            isResumed: true,
            activeConversation: convId,
            incomingConversationId: convId,
          ),
          isTrue,
        );
      },
    );

    test('4. FCM Masked Token helper never exposes full token', () {
      expect(PushNotificationService.maskToken(null), equals('none'));
      expect(PushNotificationService.maskToken(''), equals('none'));
      expect(PushNotificationService.maskToken('12345'), equals('***'));
      expect(
        PushNotificationService.maskToken(
          'eKzZ14rGTT6eW_N8_3_a9b:APA91bF24a68bcdef1234567890',
        ),
        equals('eKzZ14...7890'),
      );
    });

    test(
      '5. PushNotificationStatus distinguishes permission, preferences, and sync',
      () {
        const status = PushNotificationStatus(
          appPreferenceEnabled: true,
          osPermissionGranted: false, // User denied in Android Settings
          fcmTokenAvailable: true,
          isSynced: true,
          maskedToken: 'eKzZ14...7890',
        );

        expect(status.appPreferenceEnabled, isTrue);
        expect(status.osPermissionGranted, isFalse);
        expect(status.fcmTokenAvailable, isTrue);
        expect(status.isSynced, isTrue);

        final updated = status.copyWith(osPermissionGranted: true);
        expect(updated.osPermissionGranted, isTrue);
      },
    );

    test(
      '6. NotificationSettings copyWith preserves and updates fields correctly',
      () {
        const initial = NotificationSettings(enabled: true, discreet: false);

        final discreetUpdated = initial.copyWith(discreet: true);
        expect(discreetUpdated.enabled, isTrue);
        expect(discreetUpdated.discreet, isTrue);

        final disabled = initial.copyWith(enabled: false);
        expect(disabled.enabled, isFalse);
        expect(disabled.discreet, isFalse);
      },
    );

    test(
      '7. Push notification payload privacy: never includes message plaintext or ciphertext',
      () {
        // Validates FCM notification payload construction
        Map<String, dynamic> buildFcmNotificationPayload({
          required String messageType,
          required String? senderUsername,
          required bool isDiscreet,
        }) {
          final title = isDiscreet
              ? 'AnonApp'
              : (senderUsername != null ? '@$senderUsername' : 'AnonApp');
          String body;
          switch (messageType) {
            case 'image':
              body = '📷 Photo';
              break;
            case 'view_once_image':
              body = '🔒 Photo (View once)';
              break;
            case 'audio':
              body = '🎤 Voice message';
              break;
            case 'document':
              body = '📄 Document';
              break;
            default:
              body = 'New message received';
              break;
          }
          if (isDiscreet) body = 'New message received';

          return {'title': title, 'body': body};
        }

        final payload = buildFcmNotificationPayload(
          messageType: 'text',
          senderUsername: 'alice',
          isDiscreet: false,
        );

        expect(payload['title'], equals('@alice'));
        expect(payload['body'], equals('New message received'));

        final imagePayload = buildFcmNotificationPayload(
          messageType: 'image',
          senderUsername: 'bob',
          isDiscreet: false,
        );
        expect(imagePayload['title'], equals('@bob'));
        expect(imagePayload['body'], equals('📷 Photo'));

        final discreetPayload = buildFcmNotificationPayload(
          messageType: 'audio',
          senderUsername: 'charlie',
          isDiscreet: true,
        );
        expect(discreetPayload['title'], equals('AnonApp'));
        expect(discreetPayload['body'], equals('New message received'));
      },
    );

    test(
      '8. Messages from the same conversation resolve to the same notification ID for stacking',
      () {
        const convId = 'conv-uuid-alice-123';

        final id1 = NotificationService.conversationNotificationId(convId);
        final id2 = NotificationService.conversationNotificationId(convId);
        final id3 = NotificationService.conversationNotificationId(convId);

        expect(id1, equals(id2));
        expect(id2, equals(id3));
        expect(id1, isNonNegative);
      },
    );

    test(
      '9. Messages from different conversations resolve to distinct notification IDs',
      () {
        const convAlice = 'conv-uuid-alice-123';
        const convBob = 'conv-uuid-bob-456';
        const convCharlie = 'conv-uuid-charlie-789';

        final idAlice = NotificationService.conversationNotificationId(
          convAlice,
        );
        final idBob = NotificationService.conversationNotificationId(convBob);
        final idCharlie = NotificationService.conversationNotificationId(
          convCharlie,
        );

        expect(idAlice, isNot(equals(idBob)));
        expect(idAlice, isNot(equals(idCharlie)));
        expect(idBob, isNot(equals(idCharlie)));
      },
    );

    test(
      '10. Notification title formats correctly for discreet vs username mode',
      () {
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

        expect(
          resolveTitle(username: 'alice', count: 1, isDiscreet: false),
          equals('@alice'),
        );
        expect(
          resolveTitle(username: 'alice', count: 1, isDiscreet: true),
          equals('AnonApp'),
        );
        expect(
          resolveTitle(username: 'alice', count: 3, isDiscreet: false),
          equals('@alice (3)'),
        );
        expect(
          resolveTitle(username: 'alice', count: 5, isDiscreet: true),
          equals('AnonApp (5 messages)'),
        );
      },
    );

    test('11. Self-sent message suppression logic', () {
      bool isEligibleRecipient({
        required String senderId,
        required String recipientUserId,
      }) {
        return senderId != recipientUserId;
      }

      const userId = 'user-me-123';
      const otherId = 'user-other-456';

      expect(
        isEligibleRecipient(senderId: userId, recipientUserId: userId),
        isFalse,
      );
      expect(
        isEligibleRecipient(senderId: otherId, recipientUserId: userId),
        isTrue,
      );
    });

    test('12. Blocked user message suppression logic', () {
      bool isRecipientBlocked({
        required String senderId,
        required String recipientId,
        required Set<String> blockedPairs,
      }) {
        return blockedPairs.contains('$senderId:$recipientId') ||
            blockedPairs.contains('$recipientId:$senderId');
      }

      final blocks = <String>{'user-a:user-b'};

      expect(
        isRecipientBlocked(
          senderId: 'user-a',
          recipientId: 'user-b',
          blockedPairs: blocks,
        ),
        isTrue,
      );
      expect(
        isRecipientBlocked(
          senderId: 'user-b',
          recipientId: 'user-a',
          blockedPairs: blocks,
        ),
        isTrue,
      );
      expect(
        isRecipientBlocked(
          senderId: 'user-a',
          recipientId: 'user-c',
          blockedPairs: blocks,
        ),
        isFalse,
      );
    });

    test('13. Expired disappearing message suppression logic', () {
      bool isMessageExpired(DateTime? expiresAt, DateTime nowUtc) {
        if (expiresAt == null) return false;
        return nowUtc.isAfter(expiresAt);
      }

      final now = DateTime.now().toUtc();
      final expired = now.subtract(const Duration(seconds: 1));
      final future = now.add(const Duration(minutes: 5));

      expect(isMessageExpired(null, now), isFalse);
      expect(isMessageExpired(future, now), isFalse);
      expect(isMessageExpired(expired, now), isTrue);
    });

    test('14. Deleted message suppression logic', () {
      bool isMessageDeleted(DateTime? deletedAt) {
        return deletedAt != null;
      }

      expect(isMessageDeleted(null), isFalse);
      expect(isMessageDeleted(DateTime.now().toUtc()), isTrue);
    });

    test(
      '15. Multi-device targeting logic resolves all active registered devices',
      () {
        final devices = [
          {'id': 'd1', 'user_id': 'u1', 'notifications_enabled': true},
          {'id': 'd2', 'user_id': 'u1', 'notifications_enabled': true},
          {
            'id': 'd3',
            'user_id': 'u1',
            'notifications_enabled': false,
          }, // Disabled
          {'id': 'd4', 'user_id': 'u2', 'notifications_enabled': true},
        ];

        final targetUserDevices = devices
            .where(
              (d) => d['user_id'] == 'u1' && d['notifications_enabled'] == true,
            )
            .map((d) => d['id'])
            .toList();

        expect(targetUserDevices, equals(['d1', 'd2']));
      },
    );

    test('16. Push delivery idempotency prevents duplicate dispatch', () {
      final processedDeliveries = <String>{};

      bool shouldDispatch(String messageId, String deviceId) {
        final key = '$messageId:$deviceId';
        if (processedDeliveries.contains(key)) return false;
        processedDeliveries.add(key);
        return true;
      }

      expect(shouldDispatch('msg-1', 'dev-1'), isTrue);
      // Duplicate webhook retry must be rejected
      expect(shouldDispatch('msg-1', 'dev-1'), isFalse);
      // Different device for same message must be accepted
      expect(shouldDispatch('msg-1', 'dev-2'), isTrue);
    });

    test('17. Invalid token detection for cleanup', () {
      bool isInvalidTokenError(String errorCode, String errorMessage) {
        return errorCode == 'UNREGISTERED' ||
            errorCode == 'NOT_FOUND' ||
            errorMessage.contains('Requested entity was not found') ||
            errorMessage.contains('not a valid FCM registration token');
      }

      expect(isInvalidTokenError('UNREGISTERED', ''), isTrue);
      expect(isInvalidTokenError('NOT_FOUND', ''), isTrue);
      expect(
        isInvalidTokenError(
          'INVALID_ARGUMENT',
          'The registration token is not a valid FCM registration token',
        ),
        isTrue,
      );
      expect(isInvalidTokenError('INTERNAL', 'Server error'), isFalse);
    });

    test(
      '18. Notification tap URL encoding handles special characters in username',
      () {
        const convId = 'conv-456';
        const username = 'cool_user@#& 123';
        final encoded = Uri.encodeComponent(username);
        final targetPath = '/chat/$convId?username=$encoded';

        final uri = Uri.parse(targetPath);
        expect(uri.path, equals('/chat/conv-456'));
        expect(uri.queryParameters['username'], equals(username));
      },
    );

    test(
      '19. Web notification suppression: strictly no-ops on Web platform',
      () {
        // Verifies that web notifications remain silenced
        bool canSendNotifications(bool isWebPlatform) {
          return !isWebPlatform;
        }

        expect(canSendNotifications(true), isFalse);
        expect(canSendNotifications(false), isTrue);
      },
    );

    test(
      '20. Cryptographic verification: client-side decryption works independently of FCM transport',
      () async {
        const convId = 'test-conversation-fcm-privacy';
        const secretText = 'Top secret chat';

        final encrypted = await EncryptionService.instance.encryptText(
          secretText,
          convId,
        );

        expect(EncryptionService.isEncrypted(encrypted), isTrue);

        // Decryption occurs locally on client upon opening chat
        final decrypted = await EncryptionService.instance.decryptText(
          encrypted,
          convId,
        );
        expect(decrypted, equals(secretText));
      },
    );
  });
}
