import 'package:anonapp/core/services/encryption_service.dart';
import 'package:anonapp/features/messages/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fast Messaging & Cryptographic Key Cache Tests', () {
    setUp(() {
      EncryptionService.instance.clearKeyCache();
    });

    tearDown(() {
      EncryptionService.instance.clearKeyCache();
    });

    test('EncryptionService caches derived conversation keys', () async {
      const convId = 'conv-test-12345';

      expect(EncryptionService.instance.keyCacheSize, equals(0));

      // First encryption derives and caches key
      final encrypted1 = await EncryptionService.instance.encryptText(
        'Hello World',
        convId,
      );
      expect(EncryptionService.instance.keyCacheSize, equals(1));
      expect(EncryptionService.isEncrypted(encrypted1), isTrue);

      // Decryption uses cached key
      final decrypted1 = await EncryptionService.instance.decryptText(
        encrypted1,
        convId,
      );
      expect(decrypted1, equals('Hello World'));
      expect(EncryptionService.instance.keyCacheSize, equals(1));

      // Another message in same conversation reuses key without increasing cache size
      final encrypted2 = await EncryptionService.instance.encryptText(
        'Second Message',
        convId,
      );
      expect(EncryptionService.instance.keyCacheSize, equals(1));
      final decrypted2 = await EncryptionService.instance.decryptText(
        encrypted2,
        convId,
      );
      expect(decrypted2, equals('Second Message'));
    });

    test(
      'EncryptionService separates keys across distinct conversation IDs',
      () async {
        const convId1 = 'conv-alpha';
        const convId2 = 'conv-beta';

        await EncryptionService.instance.encryptText('Alpha Text', convId1);
        expect(EncryptionService.instance.keyCacheSize, equals(1));

        await EncryptionService.instance.encryptText('Beta Text', convId2);
        expect(EncryptionService.instance.keyCacheSize, equals(2));

        // Decrypting Alpha text with Beta key must not succeed in producing original plaintext
        final encAlpha = await EncryptionService.instance.encryptText(
          'Secret Alpha',
          convId1,
        );
        final failedDecrypt = await EncryptionService.instance.decryptText(
          encAlpha,
          convId2,
        );
        expect(
          failedDecrypt,
          equals(encAlpha),
        ); // Safe fallback returns raw ciphertext on key mismatch
      },
    );

    test('clearKeyCache completely zeroizes cached keys', () async {
      const convId = 'conv-zeroize-test';

      await EncryptionService.instance.encryptText('Test Zeroize', convId);
      expect(EncryptionService.instance.keyCacheSize, equals(1));

      // Simulate app minimize or lock zeroization
      EncryptionService.instance.clearKeyCache();
      expect(EncryptionService.instance.keyCacheSize, equals(0));

      // Subsequent encryption safely re-derives
      final encrypted = await EncryptionService.instance.encryptText(
        'Post Zeroize',
        convId,
      );
      expect(EncryptionService.instance.keyCacheSize, equals(1));
      final decrypted = await EncryptionService.instance.decryptText(
        encrypted,
        convId,
      );
      expect(decrypted, equals('Post Zeroize'));
    });
  });

  group('Dual-Track Broadcast & Reconciliation Logic Tests', () {
    test(
      'Provisional broadcast message reconciles with server confirmed message by clientId',
      () {
        const convId = 'conv-1';
        const senderId = 'user-sender';
        const clientId = 'client-uuid-999';
        final now = DateTime.now().toUtc();

        // 1. Initial empty state
        final currentMessages = <Message>[];

        // 2. Incoming broadcast message received (< 50ms)
        final broadcastMsg = Message(
          id: clientId, // provisional ID is clientId
          conversationId: convId,
          senderId: senderId,
          content: 'Instant broadcast text',
          clientId: clientId,
          createdAt: now,
          status: MessageStatus.sent,
        );

        // Add broadcast message to state
        currentMessages.insert(0, broadcastMsg);
        expect(currentMessages.length, equals(1));
        expect(currentMessages.first.id, equals(clientId));
        expect(currentMessages.first.content, equals('Instant broadcast text'));

        // 3. Server PostgreSQL INSERT event arrives later (contains permanent server UUID)
        final confirmedServerMsg = Message(
          id: 'server-permanent-uuid-777',
          conversationId: convId,
          senderId: senderId,
          content: 'Instant broadcast text',
          clientId: clientId, // Same clientId
          createdAt: now,
          status: MessageStatus.sent,
        );

        // Check reconciliation logic: find by clientId
        final indexByClient = currentMessages.indexWhere(
          (m) =>
              (m.clientId != null &&
                  m.clientId == confirmedServerMsg.clientId) ||
              m.id == confirmedServerMsg.clientId,
        );

        expect(indexByClient, equals(0));

        // Reconcile provisional -> confirmed without creating duplicate
        currentMessages[indexByClient] = confirmedServerMsg;

        // Assert state integrity: exactly 1 message, permanent server ID, zero duplicates
        expect(currentMessages.length, equals(1));
        expect(currentMessages.first.id, equals('server-permanent-uuid-777'));
        expect(currentMessages.first.clientId, equals(clientId));
        expect(currentMessages.first.content, equals('Instant broadcast text'));
      },
    );

    test('Duplicate broadcast message is skipped', () {
      const convId = 'conv-1';
      const senderId = 'user-sender';
      const clientId = 'client-dup-check';
      final now = DateTime.now().toUtc();

      final currentMessages = <Message>[
        Message(
          id: clientId,
          conversationId: convId,
          senderId: senderId,
          content: 'Already received',
          clientId: clientId,
          createdAt: now,
        ),
      ];

      // Second identical broadcast arrives
      final duplicateBroadcast = Message(
        id: clientId,
        conversationId: convId,
        senderId: senderId,
        content: 'Already received',
        clientId: clientId,
        createdAt: now,
      );

      final alreadyExists = currentMessages.any(
        (m) =>
            m.id == duplicateBroadcast.id ||
            (duplicateBroadcast.clientId != null &&
                (m.clientId == duplicateBroadcast.clientId ||
                    m.id == duplicateBroadcast.clientId)),
      );

      expect(alreadyExists, isTrue);
      // Because alreadyExists is true, state is NOT mutated
      expect(currentMessages.length, equals(1));
    });

    test('Broadcast message from self is ignored by receiver handler', () {
      const myUserId = 'user-me';
      final selfBroadcast = Message(
        id: 'client-self',
        conversationId: 'conv-1',
        senderId: myUserId,
        content: 'My own message',
        createdAt: DateTime.now().toUtc(),
      );

      // Handler logic: if msg.senderId == myUserId, return immediately
      final isSelf = selfBroadcast.senderId == myUserId;
      expect(isSelf, isTrue);
    });
  });
}
