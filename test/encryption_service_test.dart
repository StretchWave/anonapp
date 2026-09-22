import 'dart:convert';

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

    test('encrypts and decrypts audio bytes round-trip accurately', () async {
      // Mock realistic audio data (e.g. AAC/MP4 audio header and payload bytes)
      final originalBytes = List<int>.generate(256, (i) => (i * 7 + 13) % 256);

      final ciphertext = await service.encryptAudioBytes(
        originalBytes,
        conversationId1,
      );

      expect(EncryptionService.isAudioEncrypted(ciphertext), isTrue);
      expect(ciphertext, startsWith('ENC_AUDIO:v1:'));

      final decryptedBytes = await service.decryptAudioBytes(
        ciphertext,
        conversationId1,
      );

      expect(decryptedBytes, isNotNull);
      expect(decryptedBytes, equals(originalBytes));
    });

    test('generates unique nonces for repeated audio encryptions', () async {
      final audioBytes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

      final enc1 = await service.encryptAudioBytes(audioBytes, conversationId1);
      final enc2 = await service.encryptAudioBytes(audioBytes, conversationId1);

      expect(enc1, isNot(equals(enc2)));

      final parts1 = enc1
          .substring(EncryptionService.audioPrefix.length)
          .split(':');
      final parts2 = enc2
          .substring(EncryptionService.audioPrefix.length)
          .split(':');

      // Nonce (first part) must be cryptographically unique per encryption
      expect(parts1[0], isNot(equals(parts2[0])));

      // Both must still decrypt to the exact original bytes
      final dec1 = await service.decryptAudioBytes(enc1, conversationId1);
      final dec2 = await service.decryptAudioBytes(enc2, conversationId1);
      expect(dec1, equals(audioBytes));
      expect(dec2, equals(audioBytes));
    });

    test(
      'tampered audio ciphertext fails authentication and returns null safely',
      () async {
        final audioBytes = [10, 20, 30, 40, 50, 60, 70, 80];
        final ciphertext = await service.encryptAudioBytes(
          audioBytes,
          conversationId1,
        );

        const prefix = EncryptionService.audioPrefix;
        final parts = ciphertext.substring(prefix.length).split(':');
        final nonce = parts[0];
        final cipher = parts[1];
        final mac = parts[2];

        // 1. Tamper ciphertext payload
        final tamperedCipher =
            cipher.substring(0, cipher.length - 2) +
            (cipher.endsWith('A') ? 'B' : 'A');
        final tamperedPayload1 = '$prefix$nonce:$tamperedCipher:$mac';
        final res1 = await service.decryptAudioBytes(
          tamperedPayload1,
          conversationId1,
        );
        expect(res1, isNull);

        // 2. Tamper MAC authentication tag
        final tamperedMac =
            mac.substring(0, mac.length - 2) + (mac.endsWith('A') ? 'B' : 'A');
        final tamperedPayload2 = '$prefix$nonce:$cipher:$tamperedMac';
        final res2 = await service.decryptAudioBytes(
          tamperedPayload2,
          conversationId1,
        );
        expect(res2, isNull);

        // 3. Tamper Nonce
        final tamperedNonce =
            nonce.substring(0, nonce.length - 2) +
            (nonce.endsWith('A') ? 'B' : 'A');
        final tamperedPayload3 = '$prefix$tamperedNonce:$cipher:$mac';
        final res3 = await service.decryptAudioBytes(
          tamperedPayload3,
          conversationId1,
        );
        expect(res3, isNull);
      },
    );

    test('decrypting audio with wrong conversation ID fails safely', () async {
      final audioBytes = [11, 22, 33, 44, 55];
      final ciphertext = await service.encryptAudioBytes(
        audioBytes,
        conversationId1,
      );

      final attemptedDecryption = await service.decryptAudioBytes(
        ciphertext,
        conversationId2,
      );

      // Must safely return null due to AES-GCM MAC failure, without crashing
      expect(attemptedDecryption, isNull);
    });

    test(
      'encryptAudio and decryptAudio base64 convenience round-trip',
      () async {
        // Base64-encoded audio sample
        final originalB64 = base64Encode(
          List<int>.generate(128, (i) => (i * 3) % 256),
        );

        final encrypted = await service.encryptAudio(
          originalB64,
          conversationId1,
        );
        expect(EncryptionService.isAudioEncrypted(encrypted), isTrue);
        expect(encrypted, startsWith('ENC_AUDIO:v1:'));
        expect(encrypted, isNot(contains(originalB64)));

        final decryptedB64 = await service.decryptAudio(
          encrypted,
          conversationId1,
        );
        expect(decryptedB64, equals(originalB64));
      },
    );

    test(
      'decryptAudio preserves legacy unencrypted audio (backward compatibility)',
      () async {
        // Legacy voice message payload is plain base64 without ENC_AUDIO:v1: prefix
        final legacyBase64Audio = base64Encode([0x00, 0x01, 0x02, 0x03, 0xFF]);

        expect(EncryptionService.isAudioEncrypted(legacyBase64Audio), isFalse);

        final result = await service.decryptAudio(
          legacyBase64Audio,
          conversationId1,
        );

        // Passes through unmodified
        expect(result, equals(legacyBase64Audio));
      },
    );

    test(
      'malformed audio ciphertext returns null safely without throwing',
      () async {
        expect(
          await service.decryptAudioBytes(
            'ENC_AUDIO:v1:corrupt',
            conversationId1,
          ),
          isNull,
        );
        expect(
          await service.decryptAudioBytes(
            'ENC_AUDIO:v1:bad:data:format',
            conversationId1,
          ),
          isNull,
        );
        expect(await service.decryptAudioBytes('', conversationId1), isNull);
        expect(
          await service.decryptAudio(
            'ENC_AUDIO:v1:invalid:ciphertext:mac',
            conversationId1,
          ),
          isNull,
        );
      },
    );
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
