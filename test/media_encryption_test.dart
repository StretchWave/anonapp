import 'dart:convert';
import 'dart:typed_data';

import 'package:anonapp/core/services/encryption_service.dart';
import 'package:anonapp/features/messages/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Full E2EE Media & Video Encryption Tests', () {
    const testConvId = 'd7e26a29-bdf3-4c91-a1e6-34d1935e4789';
    const otherConvId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

    final sampleImageBytes = Uint8List.fromList(
      List.generate(256, (i) => (i * 7) % 256),
    );
    final sampleBase64Image = base64Encode(sampleImageBytes);

    final sampleVideoBytes = Uint8List.fromList(
      List.generate(512, (i) => (i * 13) % 256),
    );
    final sampleBase64Video = base64Encode(sampleVideoBytes);

    test('Encrypts and decrypts image bytes round-trip accurately', () async {
      final ciphertext = await EncryptionService.instance.encryptImageBytes(
        sampleImageBytes,
        testConvId,
      );

      expect(ciphertext.startsWith('ENC_IMG:v1:'), isTrue);
      expect(EncryptionService.isImageEncrypted(ciphertext), isTrue);
      expect(EncryptionService.isMediaEncrypted(ciphertext), isTrue);

      final decrypted = await EncryptionService.instance.decryptImageBytes(
        ciphertext,
        testConvId,
      );
      expect(decrypted, isNotNull);
      expect(decrypted, equals(sampleImageBytes));
    });

    test('Encrypts and decrypts base64 image round-trip', () async {
      final ciphertext = await EncryptionService.instance.encryptImage(
        sampleBase64Image,
        testConvId,
      );

      expect(ciphertext.startsWith('ENC_IMG:v1:'), isTrue);

      final decryptedB64 = await EncryptionService.instance.decryptImage(
        ciphertext,
        testConvId,
      );
      expect(decryptedB64, isNotNull);
      expect(decryptedB64, equals(sampleBase64Image));
    });

    test('Encrypts and decrypts video bytes round-trip accurately', () async {
      final ciphertext = await EncryptionService.instance.encryptVideoBytes(
        sampleVideoBytes,
        testConvId,
      );

      expect(ciphertext.startsWith('ENC_VID:v1:'), isTrue);
      expect(EncryptionService.isVideoEncrypted(ciphertext), isTrue);
      expect(EncryptionService.isMediaEncrypted(ciphertext), isTrue);

      final decrypted = await EncryptionService.instance.decryptVideoBytes(
        ciphertext,
        testConvId,
      );
      expect(decrypted, isNotNull);
      expect(decrypted, equals(sampleVideoBytes));
    });

    test('Encrypts and decrypts base64 video round-trip', () async {
      final ciphertext = await EncryptionService.instance.encryptVideo(
        sampleBase64Video,
        testConvId,
      );

      expect(ciphertext.startsWith('ENC_VID:v1:'), isTrue);

      final decryptedB64 = await EncryptionService.instance.decryptVideo(
        ciphertext,
        testConvId,
      );
      expect(decryptedB64, isNotNull);
      expect(decryptedB64, equals(sampleBase64Video));
    });

    test(
      'Tampered image or video ciphertext fails safely and returns null',
      () async {
        final imageEnc = await EncryptionService.instance.encryptImage(
          sampleBase64Image,
          testConvId,
        );
        final tamperedImage =
            '${imageEnc.substring(0, imageEnc.length - 6)}AAAAAA';
        final decryptedTamperedImage = await EncryptionService.instance
            .decryptImage(tamperedImage, testConvId);
        expect(decryptedTamperedImage, isNull);

        final videoEnc = await EncryptionService.instance.encryptVideo(
          sampleBase64Video,
          testConvId,
        );
        final tamperedVideo =
            '${videoEnc.substring(0, videoEnc.length - 6)}AAAAAA';
        final decryptedTamperedVideo = await EncryptionService.instance
            .decryptVideo(tamperedVideo, testConvId);
        expect(decryptedTamperedVideo, isNull);
      },
    );

    test(
      'Decrypting image or video with wrong conversation ID fails safely',
      () async {
        final imageEnc = await EncryptionService.instance.encryptImage(
          sampleBase64Image,
          testConvId,
        );
        final decryptedWrongImage = await EncryptionService.instance
            .decryptImage(imageEnc, otherConvId);
        expect(decryptedWrongImage, isNull);

        final videoEnc = await EncryptionService.instance.encryptVideo(
          sampleBase64Video,
          testConvId,
        );
        final decryptedWrongVideo = await EncryptionService.instance
            .decryptVideo(videoEnc, otherConvId);
        expect(decryptedWrongVideo, isNull);
      },
    );

    test(
      'Legacy unencrypted media passes through unmodified for backward compatibility',
      () async {
        const legacyRawBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

        final resultImage = await EncryptionService.instance.decryptImage(
          legacyRawBase64,
          testConvId,
        );
        expect(resultImage, equals(legacyRawBase64));

        final resultVideo = await EncryptionService.instance.decryptVideo(
          legacyRawBase64,
          testConvId,
        );
        expect(resultVideo, equals(legacyRawBase64));
      },
    );

    test('Message model properly parses reply quoting metadata', () {
      final jsonWithReply = {
        'id': 'msg-123',
        'conversation_id': testConvId,
        'sender_id': 'user-1',
        'content': 'This is a reply message',
        'message_type': 'text',
        'media_meta': {
          'reply_to_id': 'parent-msg-001',
          'reply_to_content': 'Hello, original message!',
          'reply_to_sender': '@alice',
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final msg = Message.fromJson(jsonWithReply);
      expect(msg.hasReply, isTrue);
      expect(msg.replyToId, equals('parent-msg-001'));
      expect(msg.replyToContent, equals('Hello, original message!'));
      expect(msg.replyToSender, equals('@alice'));
    });
  });
}
