import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/supabase_constants.dart';
import '../../../core/errors/error_handler.dart';
import '../domain/models/conversation.dart';

/// Repository for conversation CRUD operations.
class ConversationRepository {
  ConversationRepository(this._client);

  final SupabaseClient _client;

  /// Get all conversations for the current user, enriched with the other
  /// member's username, last message, and unread count.
  Future<List<Conversation>> getConversations() async {
    try {
      final userId = _client.auth.currentUser!.id;

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
                .select('id, username')
                .inFilter('id', uniqueOtherIds);

      final profileMap = {
        for (final p in profiles) p['id'] as String: p['username'] as String,
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

        conversations.add(
          Conversation.fromJson(row).copyWith(
            otherMemberId: otherUserId,
            otherMemberUsername: otherUserId != null
                ? profileMap[otherUserId]
                : null,
            isMuted: myMembership?['is_muted'] as bool? ?? false,
          ),
        );
      }

      return conversations;
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
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
