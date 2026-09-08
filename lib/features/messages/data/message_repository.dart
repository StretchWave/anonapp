import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/services/encryption_service.dart';
import '../domain/models/message.dart';

/// Result of fetching messages, including the conversation's [clearedAt] timestamp.
class MessagesFetchResult {
  const MessagesFetchResult({required this.messages, this.clearedAt});

  final List<Message> messages;
  final DateTime? clearedAt;
}

/// Repository handling message persistence and Supabase Realtime synchronization.
class MessageRepository {
  MessageRepository(this._client);

  final SupabaseClient _client;

  /// Current authenticated user ID.
  String get _currentUserId => _client.auth.currentUser!.id;

  /// Fetch messages for a conversation ordered from newest to oldest.
  Future<MessagesFetchResult> getMessages(
    String conversationId, {
    int limit = 50,
    DateTime? before,
  }) async {
    try {
      DateTime? clearedAt;
      try {
        final conv = await _client
            .from(SupabaseConstants.conversationsTable)
            .select('cleared_at')
            .eq('id', conversationId)
            .maybeSingle();
        if (conv != null && conv['cleared_at'] != null) {
          clearedAt = DateTime.tryParse(conv['cleared_at'] as String);
        }
      } catch (_) {}

      var query = _client
          .from(SupabaseConstants.messagesTable)
          .select()
          .eq('conversation_id', conversationId);

      if (clearedAt != null) {
        query = query.gt('created_at', clearedAt.toIso8601String());
      }

      if (before != null) {
        query = query.lt('created_at', before.toIso8601String());
      }

      // Filter out expired disappearing messages at query level
      final nowIso = DateTime.now().toUtc().toIso8601String();
      query = query.or('expires_at.is.null,expires_at.gt.$nowIso');

      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);

      final nowUtc = DateTime.now().toUtc();
      final messages = <Message>[];
      for (final r in rows) {
        var msg = Message.fromJson(r);
        if (msg.expiresAt != null && nowUtc.isAfter(msg.expiresAt!)) {
          continue;
        }
        if (msg.content != null && EncryptionService.isEncrypted(msg.content)) {
          final decrypted = await EncryptionService.instance.decryptText(
            msg.content!,
            conversationId,
          );
          msg = msg.copyWith(content: decrypted);
        }
        messages.add(msg);
      }

      return MessagesFetchResult(messages: messages, clearedAt: clearedAt);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Send a text message to a conversation.
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String? clientId,
    Duration? disappearingDuration,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      DateTime? expiresAt;
      if (disappearingDuration != null) {
        expiresAt = now.add(disappearingDuration);
      }

      final encryptedContent = await EncryptionService.instance.encryptText(
        content.trim(),
        conversationId,
      );

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'content': encryptedContent,
        'message_type': 'text',
        'created_at': now.toIso8601String(),
      };
      if (clientId != null) {
        payload['client_id'] = clientId;
      }
      if (expiresAt != null) {
        payload['expires_at'] = expiresAt.toIso8601String();
      }

      final row = await _client
          .from(SupabaseConstants.messagesTable)
          .insert(payload)
          .select()
          .single();

      final serverMessage = Message.fromJson(row);
      return serverMessage.copyWith(content: content.trim());
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Subscribe to Realtime inserts, updates, and clear_chat events for a specific conversation.
  RealtimeChannel subscribeToMessages({
    required String conversationId,
    required void Function(Message) onInsert,
    required void Function(Message) onUpdate,
    required void Function(DateTime clearedAt) onChatCleared,
  }) {
    final channel = _client.channel('messages:$conversationId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: SupabaseConstants.messagesTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty) {
              var msg = Message.fromJson(newRecord);
              if (msg.content != null &&
                  EncryptionService.isEncrypted(msg.content)) {
                final decrypted = await EncryptionService.instance.decryptText(
                  msg.content!,
                  conversationId,
                );
                msg = msg.copyWith(content: decrypted);
              }
              onInsert(msg);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: SupabaseConstants.messagesTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty) {
              var msg = Message.fromJson(newRecord);
              if (msg.content != null &&
                  EncryptionService.isEncrypted(msg.content)) {
                final decrypted = await EncryptionService.instance.decryptText(
                  msg.content!,
                  conversationId,
                );
                msg = msg.copyWith(content: decrypted);
              }
              onUpdate(msg);
            }
          },
        )
        .onBroadcast(
          event: 'clear_chat',
          callback: (payload) {
            final clearedStr = payload['cleared_at'] as String?;
            if (clearedStr != null) {
              final dt = DateTime.tryParse(clearedStr);
              if (dt != null) onChatCleared(dt);
            }
          },
        )
        .subscribe();

    return channel;
  }

  /// Clear chat for both participants without deleting rows from the database.
  Future<void> clearConversation(
    String conversationId,
    RealtimeChannel? channel,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      // 1. Broadcast immediate event to both connected users
      if (channel != null) {
        await channel.sendBroadcastMessage(
          event: 'clear_chat',
          payload: {'cleared_at': now.toIso8601String()},
        );
      }

      // 2. Persist cleared_at on conversations table
      await _client
          .from(SupabaseConstants.conversationsTable)
          .update({'cleared_at': now.toIso8601String()})
          .eq('id', conversationId);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Mark all received messages in a conversation as read.
  Future<void> markMessagesAsRead(String conversationId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // Update unread messages sent by the other user.
      await _client
          .from(SupabaseConstants.messagesTable)
          .update({'read_at': now})
          .eq('conversation_id', conversationId)
          .neq('sender_id', _currentUserId)
          .filter('read_at', 'is', null);

      // Also get the latest message ID and update conversation_members.last_read_message_id
      final latest = await _client
          .from(SupabaseConstants.messagesTable)
          .select('id')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latest != null) {
        await _client
            .from(SupabaseConstants.conversationMembersTable)
            .update({'last_read_message_id': latest['id']})
            .eq('conversation_id', conversationId)
            .eq('user_id', _currentUserId);
      }
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Soft-delete a message (only sender can delete).
  Future<void> deleteMessage(String messageId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client
          .from(SupabaseConstants.messagesTable)
          .update({
            'deleted_at': now,
            'message_type': 'deleted',
            'content': null,
          })
          .eq('id', messageId)
          .eq('sender_id', _currentUserId);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Send an image message (normal image or view-once image).
  Future<Message> sendImageMessage({
    required String conversationId,
    required String base64Image,
    String? caption,
    required bool isViewOnce,
    String? clientId,
    Duration? disappearingDuration,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      DateTime? expiresAt;
      if (disappearingDuration != null) {
        expiresAt = now.add(disappearingDuration);
      }

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'content': caption?.trim(),
        'message_type': isViewOnce ? 'view_once_image' : 'image',
        'media_data': base64Image,
        'created_at': now.toIso8601String(),
      };
      if (clientId != null) {
        payload['client_id'] = clientId;
      }
      if (expiresAt != null) {
        payload['expires_at'] = expiresAt.toIso8601String();
      }

      final row = await _client
          .from(SupabaseConstants.messagesTable)
          .insert(payload)
          .select()
          .single();

      return Message.fromJson(row);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Send a voice message with base64 encoded audio and duration.
  Future<Message> sendVoiceMessage({
    required String conversationId,
    required String base64Audio,
    required int durationMs,
    String? clientId,
  }) async {
    try {
      final now = DateTime.now().toUtc();

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'message_type': 'audio',
        'media_data': base64Audio,
        'media_meta': {'duration_ms': durationMs},
        'created_at': now.toIso8601String(),
      };
      if (clientId != null) {
        payload['client_id'] = clientId;
      }

      final row = await _client
          .from(SupabaseConstants.messagesTable)
          .insert(payload)
          .select()
          .single();

      return Message.fromJson(row);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Mark a view-once message as opened.
  Future<void> markViewOnceOpened(String messageId) async {
    try {
      await _client.rpc(
        'mark_view_once_opened',
        params: {'p_message_id': messageId},
      );
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }
}
