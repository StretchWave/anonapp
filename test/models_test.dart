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

    test('serializes and deserializes extended attributes correctly', () {
      final now = DateTime.now();
      final profile = UserProfile(
        id: 'u-999',
        username: 'cryptofox',
        displayName: 'Shadow Fox',
        contactCode: 'XYZ98765',
        createdAt: now,
        bio: 'Just another ghost in the wire',
        avatar: 'fox',
        interests: const ['Gaming', 'Coding', 'Privacy'],
        persona: 'NightCoder',
        onlineStatusVisible: false,
      );

      final json = profile.toJson();
      expect(json['bio'], 'Just another ghost in the wire');
      expect(json['avatar'], 'fox');
      expect(json['interests'], ['Gaming', 'Coding', 'Privacy']);
      expect(json['persona'], 'NightCoder');
      expect(json['online_status_visible'], false);

      final reconstructed = UserProfile.fromJson(json);
      expect(reconstructed.bio, 'Just another ghost in the wire');
      expect(reconstructed.avatar, 'fox');
      expect(reconstructed.interests, ['Gaming', 'Coding', 'Privacy']);
      expect(reconstructed.persona, 'NightCoder');
      expect(reconstructed.onlineStatusVisible, false);
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
      'retains mediaData client-side from JSON when view-once was already viewed without expiration',
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
        expect(msg.mediaData, equals('sensitive_data_saved_in_database'));
      },
    );

    test(
      'clears mediaData when view-once message is marked opened to remove recipient access',
      () {
        final now = DateTime.now().toUtc();
        final msg = Message(
          id: 'vo-access-test',
          conversationId: 'c-100',
          senderId: 'user-bob',
          messageType: MessageType.viewOnceImage,
          mediaData: 'base64_photo_bytes',
          createdAt: now,
        );

        expect(msg.isViewOnce, isTrue);
        expect(msg.isViewOnceOpened, isFalse);
        expect(msg.mediaData, equals('base64_photo_bytes'));
        expect(msg.displayText, equals('Photo (View once)'));

        // When viewed, access is removed: mediaData is cleared from memory and status becomes opened
        final viewed = msg.copyWith(viewedAt: now, clearMediaData: true);
        expect(viewed.isViewOnceOpened, isTrue);
        expect(viewed.mediaData, isNull);
        expect(viewed.displayText, equals('Photo (Opened)'));
      },
    );
    test('handles document messages correctly', () {
      final now = DateTime.now();

      // Explicit document message type
      final doc1 = Message(
        id: 'doc-1',
        conversationId: 'c-1',
        senderId: 'u-1',
        messageType: MessageType.document,
        mediaData: 'base64docbytes',
        mediaMeta: {
          'is_document': true,
          'file_name': 'project_specs.pdf',
          'file_size': 1048576,
          'mime_type': 'pdf',
        },
        createdAt: now,
      );
      expect(doc1.isDocument, isTrue);
      expect(doc1.documentFileName, 'project_specs.pdf');
      expect(doc1.documentFileSize, 1048576);
      expect(doc1.displayText, '📄 project_specs.pdf');

      // Defensive document message stored as image with is_document in media_meta
      final json = {
        'id': 'doc-2',
        'conversation_id': 'c-1',
        'sender_id': 'u-2',
        'message_type': 'image',
        'media_data': 'base64docbytes',
        'media_meta': {
          'is_document': true,
          'file_name': 'audit_report.docx',
          'file_size': 204800,
        },
        'created_at': now.toIso8601String(),
      };
      final doc2 = Message.fromJson(json);
      expect(doc2.isDocument, isTrue);
      expect(doc2.messageType, MessageType.document);
      expect(doc2.documentFileName, 'audit_report.docx');
      expect(doc2.documentFileSize, 204800);
      expect(doc2.displayText, '📄 audit_report.docx');
    });
  });
}
