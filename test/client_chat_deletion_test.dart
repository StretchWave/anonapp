import 'package:anonapp/core/services/client_chat_deletion_service.dart';
import 'package:anonapp/features/conversations/domain/models/conversation.dart';
import 'package:anonapp/features/messages/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ClientChatDeletionService', () {
    const userA = 'user-aaa-111';
    const userB = 'user-bbb-222';
    const convId1 = 'conv-1001';
    const convId2 = 'conv-1002';

    test('returns null when no chat has been deleted', () async {
      final service = ClientChatDeletionService.instance;
      final deletedAt = await service.getDeletionTimestamp(
        userId: userA,
        conversationId: convId1,
      );
      expect(deletedAt, isNull);

      final map = await service.getDeletedConversations(userA);
      expect(map, isEmpty);
    });

    test('marks chat as deleted and retrieves exact timestamp', () async {
      final service = ClientChatDeletionService.instance;
      final targetTime = DateTime.parse('2026-09-20T20:00:00.000Z');

      await service.markConversationDeleted(
        userId: userA,
        conversationId: convId1,
        timestamp: targetTime,
      );

      final deletedAt = await service.getDeletionTimestamp(
        userId: userA,
        conversationId: convId1,
      );
      expect(deletedAt, equals(targetTime));

      final allDeleted = await service.getDeletedConversations(userA);
      expect(allDeleted.containsKey(convId1), isTrue);
      expect(allDeleted[convId1], equals(targetTime));
    });

    test('guarantees user isolation for client deletions', () async {
      final service = ClientChatDeletionService.instance;
      final timeA = DateTime.parse('2026-09-20T21:00:00.000Z');

      // User A deletes chat convId1
      await service.markConversationDeleted(
        userId: userA,
        conversationId: convId1,
        timestamp: timeA,
      );

      // User B must NOT see it as deleted
      final deletedForB = await service.getDeletionTimestamp(
        userId: userB,
        conversationId: convId1,
      );
      expect(deletedForB, isNull);

      final mapForB = await service.getDeletedConversations(userB);
      expect(mapForB, isEmpty);
    });

    test('tracks multiple conversations independently', () async {
      final service = ClientChatDeletionService.instance;
      final time1 = DateTime.parse('2026-09-20T18:00:00.000Z');
      final time2 = DateTime.parse('2026-09-20T19:30:00.000Z');

      await service.markConversationDeleted(
        userId: userA,
        conversationId: convId1,
        timestamp: time1,
      );
      await service.markConversationDeleted(
        userId: userA,
        conversationId: convId2,
        timestamp: time2,
      );

      expect(
        await service.getDeletionTimestamp(
          userId: userA,
          conversationId: convId1,
        ),
        equals(time1),
      );
      expect(
        await service.getDeletionTimestamp(
          userId: userA,
          conversationId: convId2,
        ),
        equals(time2),
      );

      // Restore convId1
      await service.restoreConversation(userId: userA, conversationId: convId1);
      expect(
        await service.getDeletionTimestamp(
          userId: userA,
          conversationId: convId1,
        ),
        isNull,
      );
      expect(
        await service.getDeletionTimestamp(
          userId: userA,
          conversationId: convId2,
        ),
        equals(time2),
      );
    });
  });

  group('Conversation Filtering Logic', () {
    const convId1 = 'conv-1001';
    const convId2 = 'conv-1002';

    final baseConversation = Conversation(
      id: convId1,
      otherMemberId: 'partner-1',
      otherMemberUsername: 'Alice',
      lastMessageAt: DateTime.parse('2026-09-20T12:00:00.000Z'),
      createdAt: DateTime.parse('2026-09-20T10:00:00.000Z'),
      updatedAt: DateTime.parse('2026-09-20T12:00:00.000Z'),
    );

    final secondConversation = Conversation(
      id: convId2,
      otherMemberId: 'partner-2',
      otherMemberUsername: 'Bob',
      lastMessageAt: DateTime.parse('2026-09-20T15:00:00.000Z'),
      createdAt: DateTime.parse('2026-09-20T10:00:00.000Z'),
      updatedAt: DateTime.parse('2026-09-20T15:00:00.000Z'),
    );

    test(
      'filters out deleted conversation when lastMessageAt <= deletedAt',
      () {
        final deletedAt = DateTime.parse('2026-09-20T12:00:00.000Z');
        final deletedMap = {convId1: deletedAt};

        final conversations = [baseConversation, secondConversation];

        final filtered = conversations.where((c) {
          final d = deletedMap[c.id];
          if (d == null) return true;
          if (c.lastMessageAt == null) return false;
          return c.lastMessageAt!.isAfter(d);
        }).toList();

        expect(filtered.length, 1);
        expect(filtered.first.id, convId2);
      },
    );

    test(
      're-displays conversation when a new message arrives after deletedAt',
      () {
        final deletedAt = DateTime.parse('2026-09-20T12:00:00.000Z');
        final deletedMap = {convId1: deletedAt};

        // New message arrived at 13:00, after deletion at 12:00
        final updatedConversation = baseConversation.copyWith(
          lastMessageAt: DateTime.parse('2026-09-20T13:00:00.000Z'),
        );

        final conversations = [updatedConversation, secondConversation];

        final filtered = conversations.where((c) {
          final d = deletedMap[c.id];
          if (d == null) return true;
          if (c.lastMessageAt == null) return false;
          return c.lastMessageAt!.isAfter(d);
        }).toList();

        expect(filtered.length, 2);
        expect(filtered.map((c) => c.id), contains(convId1));
      },
    );

    test(
      'hides conversation if deletedAt exists and lastMessageAt is null',
      () {
        final deletedAt = DateTime.parse('2026-09-20T12:00:00.000Z');
        final deletedMap = {convId1: deletedAt};

        final emptyConversation = Conversation(
          id: convId1,
          otherMemberId: 'partner-1',
          otherMemberUsername: 'Alice',
          lastMessageAt: null,
          createdAt: DateTime.parse('2026-09-20T10:00:00.000Z'),
          updatedAt: DateTime.parse('2026-09-20T10:00:00.000Z'),
        );

        final conversations = [emptyConversation];

        final filtered = conversations.where((c) {
          final d = deletedMap[c.id];
          if (d == null) return true;
          if (c.lastMessageAt == null) return false;
          return c.lastMessageAt!.isAfter(d);
        }).toList();

        expect(filtered, isEmpty);
      },
    );
  });

  group('Message Filtering Logic on Client Deletion', () {
    final deletedAt = DateTime.parse('2026-09-20T14:00:00.000Z');

    final msgBefore = Message(
      id: 'msg-1',
      conversationId: 'conv-1',
      senderId: 'user-1',
      content: 'enc-1',
      createdAt: DateTime.parse('2026-09-20T13:59:59.000Z'),
    );

    final msgAt = Message(
      id: 'msg-2',
      conversationId: 'conv-1',
      senderId: 'user-1',
      content: 'enc-2',
      createdAt: DateTime.parse('2026-09-20T14:00:00.000Z'),
    );

    final msgAfter = Message(
      id: 'msg-3',
      conversationId: 'conv-1',
      senderId: 'user-2',
      content: 'enc-3',
      createdAt: DateTime.parse('2026-09-20T14:00:01.000Z'),
    );

    test('filters out messages created before or at deletedAt', () {
      final allMessages = [msgBefore, msgAt, msgAfter];

      final visibleMessages = allMessages.where((m) {
        return m.createdAt.isAfter(deletedAt);
      }).toList();

      expect(visibleMessages.length, 1);
      expect(visibleMessages.first.id, equals('msg-3'));
    });
  });
}
