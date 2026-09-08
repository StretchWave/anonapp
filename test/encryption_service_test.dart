import 'package:anonapp/core/services/encryption_service.dart';
import 'package:anonapp/core/utils/file_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EncryptionService', () {
    final service = EncryptionService.instance;
    const conversationId1 = 'conv-uuid-1111-2222';
    const conversationId2 = 'conv-uuid-3333-4444';

    test('encrypts and decrypts text successfully', () async {
      const originalText = 'Secret message between anons! 🤫';
      final encrypted = await service.encryptText(
        originalText,
        conversationId1,
      );

      expect(EncryptionService.isEncrypted(encrypted), isTrue);
      expect(encrypted, startsWith('ENC:v1:'));
      expect(encrypted, isNot(contains(originalText)));

      final decrypted = await service.decryptText(encrypted, conversationId1);
      expect(decrypted, equals(originalText));
    });

    test(
      'returns plaintext untouched if not encrypted (backwards compatibility)',
      () async {
        const legacyText = 'This is an old unencrypted message';
        expect(EncryptionService.isEncrypted(legacyText), isFalse);

        final decrypted = await service.decryptText(
          legacyText,
          conversationId1,
        );
        expect(decrypted, equals(legacyText));
      },
    );

    test(
      'fails to decrypt if wrong conversation ID is provided (returns ciphertext unmodified)',
      () async {
        const message = 'Confidential details';
        final encrypted = await service.encryptText(message, conversationId1);

        final attemptedDecryption = await service.decryptText(
          encrypted,
          conversationId2,
        );
        expect(attemptedDecryption, equals(encrypted));
        expect(attemptedDecryption, isNot(equals(message)));
      },
    );

    test('handles empty strings gracefully', () async {
      final encrypted = await service.encryptText('', conversationId1);
      final decrypted = await service.decryptText(encrypted, conversationId1);
      expect(decrypted, equals(''));
    });
  });

  group('File Cleanup', () {
    test(
      'deleteTempFile handles null and non-existent paths gracefully',
      () async {
        await expectLater(deleteTempFile(null), completes);
        await expectLater(deleteTempFile(''), completes);
        await expectLater(
          deleteTempFile('/non/existent/path/audio.m4a'),
          completes,
        );
      },
    );
  });
}
