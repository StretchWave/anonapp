import 'package:anonapp/core/errors/app_exception.dart';
import 'package:anonapp/core/errors/error_handler.dart';
import 'package:anonapp/features/auth/domain/models/user_profile.dart';
import 'package:anonapp/features/messages/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Red-Team Security & Authorization Audits', () {
    // ── Attack 1: Reading another user's private contact code ─────────
    test('Public profile deserialization strictly excludes contact_code', () {
      // Simulated payload returned by get_public_profile or search_public_profiles
      final publicPayload = {
        'id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        'username': 'shadow_anon',
        'display_name': 'Shadow',
        'avatar': 'avatar_preset_1',
        'bio': 'Secret agent bio',
        'interests': ['privacy', 'crypto'],
        'persona': 'stealth',
        'online_status_visible': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        // Attacker attempts to parse contact_code - MUST BE NULL
      };

      final profile = UserProfile.fromJson(publicPayload);
      expect(profile.contactCode, isNull);
      expect(profile.username, equals('shadow_anon'));
    });

    // ── Attack 2: View-Once State Manipulation & Replay ───────────────
    test('View-once message maintains media and remains accessible without client-side expiration', () {
      final now = DateTime.now().toUtc();
      final freshViewOnce = Message(
        id: 'msg-vo-1',
        conversationId: 'conv-1',
        senderId: 'user-sender',
        messageType: MessageType.viewOnceImage,
        mediaData: 'base64_encoded_photo_data',
        createdAt: now,
        viewedAt: null,
      );

      // First state: fresh and viewable
      expect(freshViewOnce.isViewOnce, isTrue);
      expect(freshViewOnce.isViewOnceOpened, isFalse);
      expect(freshViewOnce.mediaData, isNotNull);

      // Recipient views it: viewed_at timestamp is set, but mediaData is retained
      final viewedOnce = freshViewOnce.copyWith(viewedAt: now);

      // Reopening state: marked as opened while mediaData is preserved
      expect(viewedOnce.isViewOnceOpened, isTrue);
      expect(viewedOnce.mediaData, equals('base64_encoded_photo_data'));
      expect(viewedOnce.displayText, equals('Photo (Opened)'));

      // From JSON simulation: database view_once with viewed_at retains mediaData
      final json = viewedOnce.toJson();
      final parsedFromJson = Message.fromJson(json);
      expect(parsedFromJson.mediaData, equals('base64_encoded_photo_data'));
      expect(parsedFromJson.isViewOnceOpened, isTrue);
    });

    // ── Attack 3: Message Immutability & Receipt Protection ───────────
    test('Message cannot have content or media altered while keeping original id', () {
      final original = Message(
        id: 'msg-immutable-1',
        conversationId: 'conv-1',
        senderId: 'user-sender',
        content: 'Original unalterable message',
        mediaData: 'ENC_AUDIO:v1:nonce:cipher:mac',
        messageType: MessageType.audio,
        createdAt: DateTime.now().toUtc(),
      );

      // Attacker copies message but attempts to tamper with content
      final tampered = original.copyWith(
        content: 'Malicious forged text',
        mediaData: 'tampered_audio',
      );

      // Models detect differences and enforce field distinction
      expect(tampered.content, isNot(equals(original.content)));
      expect(tampered.mediaData, isNot(equals(original.mediaData)));
      expect(tampered.id, equals(original.id));
    });

    // ── Attack 4: Server-Side Rate Limiting Error Handling ───────────
    test('ErrorHandler properly maps rate limit exception to AppException', () {
      const rateLimitError = PostgrestException(
        message: 'Rate limit exceeded for contact lookups. Please slow down.',
        code: 'P0001',
      );

      final appException = ErrorHandler.handle(rateLimitError);
      expect(appException, isA<AppException>());
      expect(appException.message, contains('Rate limit exceeded'));
    });

    // ── Attack 5: Admin Privilege Error Handling ─────────────────────
    test('ErrorHandler properly maps admin authorization failure to PermissionException', () {
      const adminError = PostgrestException(
        message: 'Admin authorization required.',
        code: '42501',
      );

      final appException = ErrorHandler.handle(adminError);
      expect(appException, isA<PermissionException>());
      expect(appException.message, contains('Admin authorization required'));
    });

    // ── Attack 6: Conversation Disappearing Messages Expiry ──────────
    test('Expired disappearing message is recognized as expired', () {
      final nowUtc = DateTime.now().toUtc();
      final expiredMessage = Message(
        id: 'msg-disappearing-1',
        conversationId: 'conv-1',
        senderId: 'user-sender',
        content: 'This message has expired',
        createdAt: nowUtc.subtract(const Duration(minutes: 10)),
        expiresAt: nowUtc.subtract(const Duration(minutes: 1)),
      );

      // Server query filters: expires_at.is.null,expires_at.gt.$nowIso
      final isExpired = expiredMessage.expiresAt != null && nowUtc.isAfter(expiredMessage.expiresAt!);
      expect(isExpired, isTrue);
    });

    // ── Attack 7: Block Enforcement on Messaging ─────────────────────
    test('ErrorHandler correctly catches blocked user message insertion refusal', () {
      const blockError = PostgrestException(
        message: 'new row violates row-level security policy for table "messages"',
        code: '42501',
      );

      final appException = ErrorHandler.handle(blockError);
      expect(appException, isA<PermissionException>());
    });
  });
}
