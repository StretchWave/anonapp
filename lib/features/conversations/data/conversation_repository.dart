import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/supabase_constants.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/services/client_chat_deletion_service.dart';
import '../../../core/services/encryption_service.dart';
import '../domain/models/conversation.dart';

/// Repository for conversation CRUD operations.
class ConversationRepository {
  ConversationRepository(this._client);

  final SupabaseClient _client;

  /// Get all conversations for the current user, enriched with the other
  /// member's username, last message, and unread count.
  Future<List<Conversation>> getConversations() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      // Get all conversation IDs the user is a member of.
      final memberRows = await _client
          .from(SupabaseConstants.conversationMembersTable)
          .select('conversation_id')
          .eq('user_id', userId);

      if (memberRows.isEmpty) return [];

      final conversationIds = memberRows
          .map((r) => r['conversation_id'] as String)
          .toList();

      // Get conversation details.
      final convRows = await _client
          .from(SupabaseConstants.conversationsTable)
          .select()
          .inFilter('id', conversationIds)
          .order('updated_at', ascending: false);

      // Get all members of these conversations for username lookup.
      final allMembers = await _client
          .from(SupabaseConstants.conversationMembersTable)
          .select('conversation_id, user_id')
          .inFilter('conversation_id', conversationIds);

      // Get the current user's membership data (for mute/read state).
      final myMemberships = await _client
          .from(SupabaseConstants.conversationMembersTable)
          .select()
          .eq('user_id', userId)
          .inFilter('conversation_id', conversationIds);

      // Fetch unread message counts for user's conversations
      final unreadRows = await _client
          .from(SupabaseConstants.messagesTable)
          .select('conversation_id')
          .inFilter('conversation_id', conversationIds)
          .neq('sender_id', userId)
          .isFilter('read_at', null)
          .isFilter('deleted_at', null);

      final unreadCounts = <String, int>{};
      for (final r in unreadRows) {
        final cId = r['conversation_id'] as String;
        unreadCounts[cId] = (unreadCounts[cId] ?? 0) + 1;
      }

      // Fetch latest messages across these conversations for preview
      final recentMessages = await _client
          .from(SupabaseConstants.messagesTable)
          .select(
            'conversation_id, content, message_type, created_at, sender_id',
          )
          .inFilter('conversation_id', conversationIds)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(200);

      final lastMessageMap = <String, Map<String, dynamic>>{};
      for (final msg in recentMessages) {
        final cId = msg['conversation_id'] as String;
        if (!lastMessageMap.containsKey(cId)) {
          lastMessageMap[cId] = msg;
        }
      }

      // Build a map of conversationId → other user IDs.
      final otherUserIds = <String, String>{};
      for (final member in allMembers) {
        final memberId = member['user_id'] as String;
        final convId = member['conversation_id'] as String;
        if (memberId != userId) {
          otherUserIds[convId] = memberId;
        }
      }

      // Fetch profiles of other members.
      final uniqueOtherIds = otherUserIds.values.toSet().toList();
      final profiles = uniqueOtherIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client
                .from(SupabaseConstants.profilesTable)
                .select('id, username, last_seen')
                .inFilter('id', uniqueOtherIds);

      final profileMap = {
        for (final p in profiles) p['id'] as String: p['username'] as String,
      };
      final lastSeenMap = <String, DateTime?>{
        for (final p in profiles)
          if (p['last_seen'] != null)
            p['id'] as String: DateTime.tryParse(p['last_seen'] as String),
      };

      // Build my membership map.
      final myMembershipMap = {
        for (final m in myMemberships) m['conversation_id'] as String: m,
      };

      // Assemble conversations.
      final conversations = <Conversation>[];
      for (final row in convRows) {
        final convId = row['id'] as String;
        final otherUserId = otherUserIds[convId];
        final myMembership = myMembershipMap[convId];
        final lastMsg = lastMessageMap[convId];

        String? lastContent;
        if (lastMsg != null) {
          final msgType = lastMsg['message_type'] as String? ?? 'text';
          switch (msgType) {
            case 'image':
              lastContent = '📷 Photo';
              break;
            case 'view_once_image':
              lastContent = '🔒 Photo (View once)';
              break;
            case 'audio':
              lastContent = '🎤 Voice message';
              break;
            default:
              final rawContent = lastMsg['content'] as String?;
              if (rawContent != null &&
                  EncryptionService.isEncrypted(rawContent)) {
                try {
                  lastContent = await EncryptionService.instance.decryptText(
                    rawContent,
                    convId,
                  );
                } catch (_) {
                  lastContent = 'Encrypted message';
                }
              } else {
                lastContent = rawContent;
              }
              break;
          }
        }

        conversations.add(
          Conversation.fromJson(row).copyWith(
            otherMemberId: otherUserId,
            otherMemberUsername: otherUserId != null
                ? profileMap[otherUserId]
                : null,
            otherMemberLastSeen: otherUserId != null
                ? lastSeenMap[otherUserId]
                : null,
            isMuted: myMembership?['is_muted'] as bool? ?? false,
            unreadCount: unreadCounts[convId] ?? 0,
            lastMessageContent: lastContent,
            lastMessageAt: lastMsg != null && lastMsg['created_at'] != null
                ? DateTime.tryParse(lastMsg['created_at'] as String)
                : null,
            lastMessageSenderId: lastMsg?['sender_id'] as String?,
          ),
        );
      }

      // Filter out conversations deleted client-sided by the current user
      // unless a newer message has arrived after the client deletion timestamp.
      final deletedMap = await ClientChatDeletionService.instance
          .getDeletedConversations(userId);

      if (deletedMap.isNotEmpty) {
        conversations.removeWhere((conv) {
          final deletedAt = deletedMap[conv.id];
          if (deletedAt == null) return false;

          final lastAt = conv.lastMessageAt ?? conv.updatedAt;
          return !lastAt.toUtc().isAfter(deletedAt.toUtc());
        });
      }

      return conversations;
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Deletes a conversation client-sided for the current user only.
  Future<void> deleteConversationClientSided(String conversationId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await ClientChatDeletionService.instance.markConversationDeleted(
      userId: userId,
      conversationId: conversationId,
    );
  }

  /// Restores a conversation that was previously deleted client-sided.
  Future<void> restoreConversationClientSided(String conversationId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await ClientChatDeletionService.instance.restoreConversation(
      userId: userId,
      conversationId: conversationId,
    );
  }

  /// Create or find a 1:1 conversation with another user.
  /// Uses the `find_or_create_direct_conversation` DB function.
  Future<String> findOrCreateDirectConversation(String otherUserId) async {
    try {
      final userId = _client.auth.currentUser!.id;

      final result = await _client.rpc(
        'find_or_create_direct_conversation',
        params: {'p_user_id_1': userId, 'p_user_id_2': otherUserId},
      );

      return result as String;
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Toggle mute state for a conversation.
  Future<void> toggleMute(String conversationId, {required bool muted}) async {
    try {
      final userId = _client.auth.currentUser!.id;

      await _client
          .from(SupabaseConstants.conversationMembersTable)
          .update({'is_muted': muted})
          .eq('conversation_id', conversationId)
          .eq('user_id', userId);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }
}
