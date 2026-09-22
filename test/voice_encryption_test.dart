import 'dart:convert';

import 'package:anonapp/core/services/encryption_service.dart';
import 'package:anonapp/features/messages/domain/models/message.dart';
import 'package:anonapp/features/messages/presentation/widgets/message_bubble.dart';
import 'package:anonapp/features/messages/presentation/widgets/voice_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const conversationId = 'conv-test-voice-12345';
  final originalAudioBytes = [
    79,
    103,
    103,
    83,
    0,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
  ]; // OggS mock header
  final originalBase64Audio = base64Encode(originalAudioBytes);

  group('Voice Message Encryption Pipeline', () {
    test(
      'encrypted voice payload uses ENC_AUDIO:v1: format and hides original audio',
      () async {
        final encryptedPayload = await EncryptionService.instance.encryptAudio(
          originalBase64Audio,
          conversationId,
        );

        // Verify format
        expect(encryptedPayload, startsWith('ENC_AUDIO:v1:'));
        expect(EncryptionService.isAudioEncrypted(encryptedPayload), isTrue);

        // Verify plaintext base64 audio is NOT present anywhere in the ciphertext
        expect(encryptedPayload, isNot(contains(originalBase64Audio)));

        // Verify text encryption prefix is NOT matched
        expect(EncryptionService.isEncrypted(encryptedPayload), isFalse);
      },
    );

    test('decrypted voice payload recovers exact original audio', () async {
      final encryptedPayload = await EncryptionService.instance.encryptAudio(
        originalBase64Audio,
        conversationId,
      );

      final decryptedBase64 = await EncryptionService.instance.decryptAudio(
        encryptedPayload,
        conversationId,
      );

      expect(decryptedBase64, equals(originalBase64Audio));
      expect(base64Decode(decryptedBase64!), equals(originalAudioBytes));
    });

    test(
      'legacy unencrypted voice message is preserved without re-encryption',
      () async {
        // Legacy message has raw base64 in media_data without ENC_AUDIO:v1: prefix
        final legacyBase64 = originalBase64Audio;
        expect(EncryptionService.isAudioEncrypted(legacyBase64), isFalse);

        final decrypted = await EncryptionService.instance.decryptAudio(
          legacyBase64,
          conversationId,
        );

        expect(decrypted, equals(legacyBase64));
      },
    );

    test(
      'failed voice decryption returns null safely without throwing',
      () async {
        const corruptedPayload = 'ENC_AUDIO:v1:badnonce:badcipher:badmac';
        final result = await EncryptionService.instance.decryptAudio(
          corruptedPayload,
          conversationId,
        );

        expect(result, isNull);
      },
    );

    test(
      'Message model with audio deserializes and distinguishes audio from image and text',
      () {
        final json = {
          'id': 'msg-voice-1',
          'conversation_id': conversationId,
          'sender_id': 'user-1',
          'message_type': 'audio',
          'media_data': 'ENC_AUDIO:v1:dGVzdA==:dGVzdA==:dGVzdA==',
          'media_meta': {'duration_ms': 4500},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };

        final msg = Message.fromJson(json);
        expect(msg.isAudio, isTrue);
        expect(msg.isImage, isFalse);
        expect(msg.isViewOnce, isFalse);
        expect(msg.displayText, equals('Voice message'));
        expect(msg.mediaMeta?['duration_ms'], equals(4500));
      },
    );
  });

  group('Voice Message UI Safe State', () {
    testWidgets(
      'VoicePlayer displays unavailable state safely when audio payload is empty or invalid',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: VoicePlayer(
                base64Audio: 'not-valid-base-64!!!',
                isMine: false,
                totalDurationMs: 3000,
              ),
            ),
          ),
        );

        // Should not throw or crash; displays safe fallback
        expect(find.text('Voice message unavailable'), findsOneWidget);
        expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'MessageBubble displays unavailable state when voice mediaData is null',
      (tester) async {
        final corruptedAudioMessage = Message(
          id: 'msg-corrupt-1',
          conversationId: conversationId,
          senderId: 'user-2',
          messageType: MessageType.audio,
          mediaData: null, // Decryption failed
          mediaMeta: const {'duration_ms': 2000},
          createdAt: DateTime.now().toUtc(),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  message: corruptedAudioMessage,
                  isMine: false,
                  conversationId: conversationId,
                ),
              ),
            ),
          ),
        );

        // Verifies safe fallback text is rendered
        expect(find.text('Voice message unavailable'), findsOneWidget);
        expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'MessageBubble renders VoicePlayer when valid audio is present',
      (tester) async {
        final validAudioMessage = Message(
          id: 'msg-valid-1',
          conversationId: conversationId,
          senderId: 'user-2',
          messageType: MessageType.audio,
          mediaData: originalBase64Audio,
          mediaMeta: const {'duration_ms': 5000},
          createdAt: DateTime.now().toUtc(),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  message: validAudioMessage,
                  isMine: false,
                  conversationId: conversationId,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(VoicePlayer), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      },
    );
  });
}
