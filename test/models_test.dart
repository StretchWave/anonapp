import 'package:anonapp/core/env/env.dart';
import 'package:anonapp/features/auth/domain/models/user_profile.dart';
import 'package:anonapp/features/conversations/domain/models/conversation.dart';
import 'package:anonapp/features/messages/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env', () {
    test('contains configured Supabase URL and anon key', () {
      expect(Env.supabaseUrl, isNotEmpty);
      expect(Env.supabaseAnonKey, isNotEmpty);
      expect(() => Env.validate(), returnsNormally);
    });
  });

  group('UserProfile Model', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final profile = UserProfile(
        id: 'u-123',
        username: 'alice',
        displayName: 'Alice In Wonderland',
        contactCode: 'AB12CD34',
        createdAt: now,
      );

      final json = profile.toJson();
      expect(json['id'], 'u-123');
      expect(json['username'], 'alice');
      expect(json['contact_code'], 'AB12CD34');

      final reconstructed = UserProfile.fromJson(json);
      expect(reconstructed.id, profile.id);
      expect(reconstructed.username, profile.username);
      expect(reconstructed.contactCode, profile.contactCode);
    });
  });

  group('Conversation Model', () {
    test('instantiates and handles copyWith', () {
      final now = DateTime.now();
      final conv = Conversation(
        id: 'c-100',
        createdAt: now,
        updatedAt: now,
        otherMemberUsername: 'bob',
        otherMemberId: 'u-456',
        lastMessageContent: 'Hello anon!',
        unreadCount: 2,
      );

      expect(conv.otherMemberUsername, 'bob');
      expect(conv.unreadCount, 2);

      final updated = conv.copyWith(isMuted: true, unreadCount: 0);
      expect(updated.isMuted, isTrue);
      expect(updated.unreadCount, 0);
      expect(updated.id, 'c-100');
    });
  });

  group('Message Model', () {
    test('resolves delivery status and ownership properly', () {
      final now = DateTime.now();
      final msg = Message(
        id: 'm-1',
        conversationId: 'c-100',
        senderId: 'user-me',
        content: 'Top secret anonymous message',
        createdAt: now,
        status: MessageStatus.sent,
      );

      expect(msg.isMine('user-me'), isTrue);
      expect(msg.isMine('user-other'), isFalse);
      expect(msg.displayText, 'Top secret anonymous message');
      expect(msg.isDeleted, isFalse);

      final deleted = msg.copyWith(messageType: MessageType.deleted);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.displayText, 'This message was deleted');
    });

    test('parses read_at into read status from JSON', () {
      final now = DateTime.now().toIso8601String();
      final json = {
        'id': 'm-2',
        'conversation_id': 'c-100',
        'sender_id': 'user-bob',
        'content': 'Hey!',
        'message_type': 'text',
        'created_at': now,
        'read_at': now,
      };

      final msg = Message.fromJson(json);
      expect(msg.status, MessageStatus.read);
    });

    test('handles image, view-once photo, and audio messages', () {
      final now = DateTime.now();

      // Normal image
      final img = Message(
        id: 'img-1',
        conversationId: 'c-1',
        senderId: 'u-1',
        messageType: MessageType.image,
        mediaData: 'base64imagedata',
        content: 'Look at this!',
        createdAt: now,
      );
      expect(img.isImage, isTrue);
      expect(img.isViewOnce, isFalse);
      expect(img.displayText, 'Look at this!');

      // View once image
      final viewOnce = Message(
        id: 'vo-1',
        conversationId: 'c-1',
        senderId: 'u-1',
        messageType: MessageType.viewOnceImage,
        mediaData: 'sensitivebytes',
        createdAt: now,
      );
      expect(viewOnce.isViewOnce, isTrue);
      expect(viewOnce.isViewOnceOpened, isFalse);
      expect(viewOnce.displayText, 'Photo (View once)');

      final opened = viewOnce.copyWith(viewedAt: now, mediaData: null);
      expect(opened.isViewOnceOpened, isTrue);
      expect(opened.displayText, 'Photo (Opened)');

      // Audio message
      final audio = Message(
        id: 'aud-1',
        conversationId: 'c-1',
        senderId: 'u-1',
        messageType: MessageType.audio,
        mediaData: 'base64audio',
        mediaMeta: {'duration_ms': 5400},
        createdAt: now,
      );
      expect(audio.isAudio, isTrue);
      expect(audio.displayText, 'Voice message');
      expect(audio.mediaMeta?['duration_ms'], 5400);
    });

    test(
      'strips mediaData client-side from JSON when view-once was already viewed',
      () {
        final now = DateTime.now().toIso8601String();
        final json = {
          'id': 'vo-2',
          'conversation_id': 'c-100',
          'sender_id': 'user-bob',
          'message_type': 'view_once_image',
          'media_data': 'sensitive_data_saved_in_database',
          'created_at': now,
          'viewed_at': now,
        };

        final msg = Message.fromJson(json);
        expect(msg.isViewOnce, isTrue);
        expect(msg.isViewOnceOpened, isTrue);
        expect(msg.mediaData, isNull);
      },
    );
  });
}
