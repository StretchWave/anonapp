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
        msg = await _decryptMessagePayload(msg, conversationId);
        messages.add(msg);
      }

      return MessagesFetchResult(messages: messages, clearedAt: clearedAt);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  Future<Message> _decryptMessagePayload(
    Message msg,
    String conversationId,
  ) => decryptMessagePayload(msg, conversationId);

  /// Decrypts text content and voice audio payloads locally for a message.
  Future<Message> decryptMessagePayload(
    Message msg,
    String conversationId,
  ) async {
    var result = msg;
    if (result.content != null && EncryptionService.isEncrypted(result.content)) {
      final decrypted = await EncryptionService.instance.decryptText(
        result.content!,
        conversationId,
      );
      result = result.copyWith(content: decrypted);
    }
    if (result.isAudio &&
        result.mediaData != null &&
        EncryptionService.isAudioEncrypted(result.mediaData)) {
      final decryptedAudio = await EncryptionService.instance.decryptAudio(
        result.mediaData!,
        conversationId,
      );
      result = result.copyWith(mediaData: decryptedAudio);
    }
    if (result.isViewOnce && result.isViewOnceOpened) {
      // Access removed: strip mediaData client-side for already-viewed view-once media,
      // while preserving raw encrypted payload intact on the Supabase server.
      result = result.copyWith(clearMediaData: true);
    } else if ((result.isImage || result.isViewOnce || result.isDocument) &&
        result.mediaData != null &&
        EncryptionService.isImageEncrypted(result.mediaData)) {
      final decryptedImage = await EncryptionService.instance.decryptImage(
        result.mediaData!,
        conversationId,
      );
      result = result.copyWith(mediaData: decryptedImage);
    }
    if (result.mediaData != null &&
        EncryptionService.isVideoEncrypted(result.mediaData)) {
      final decryptedVideo = await EncryptionService.instance.decryptVideo(
        result.mediaData!,
        conversationId,
      );
      result = result.copyWith(mediaData: decryptedVideo);
    }
    return result;
  }

  /// Send a text message to a conversation.
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String? clientId,
    Duration? disappearingDuration,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
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
      if (replyToId != null) {
        payload['media_meta'] = {
          'reply_to_id': replyToId,
          'reply_to_content': replyToContent,
          'reply_to_sender': replyToSender,
        };
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
    void Function(String senderId)? onTyping,
    void Function(Message)? onDirectMessageBroadcast,
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
              msg = await _decryptMessagePayload(msg, conversationId);
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
              msg = await _decryptMessagePayload(msg, conversationId);
              onUpdate(msg);
            }
          },
        )
        .onBroadcast(
          event: 'direct_message',
          callback: (payload) async {
            try {
              final raw = payload['message'];
              if (raw is Map<String, dynamic> && raw.isNotEmpty) {
                final senderId = raw['sender_id'] as String?;
                if (senderId == _currentUserId) return;
                var msg = Message.fromJson(raw);
                msg = await _decryptMessagePayload(msg, conversationId);
                onDirectMessageBroadcast?.call(msg);
              }
            } catch (_) {}
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
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final senderId = payload['sender_id'] as String?;
            if (senderId != null) {
              onTyping?.call(senderId);
            }
          },
        )
        .subscribe();

    return channel;
  }

  /// Broadcasts an encrypted message payload instantly across the WebSocket channel (< 50ms)
  /// concurrently with the PostgreSQL database persistence call.
  Future<void> broadcastDirectMessage({
    required RealtimeChannel? channel,
    required Map<String, dynamic> payload,
  }) async {
    if (channel == null) return;
    try {
      await channel.sendBroadcastMessage(
        event: 'direct_message',
        payload: {'message': payload},
      );
    } catch (_) {
      // Non-fatal broadcast failure; PostgreSQL insert is running in parallel
    }
  }

  /// Broadcast typing event to conversation channel.
  Future<void> sendTyping(RealtimeChannel? channel) async {
    if (channel != null) {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'sender_id': _currentUserId},
      );
    }
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

      // 2. Persist cleared_at using secure RPC (or fallback to update)
      try {
        await _client.rpc(
          'clear_conversation_chat',
          params: {'p_conversation_id': conversationId},
        );
      } catch (_) {
        await _client
            .from(SupabaseConstants.conversationsTable)
            .update({'cleared_at': now.toIso8601String()})
            .eq('id', conversationId);
      }
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
  /// Image payload is encrypted with AES-256-GCM locally before storage in Supabase.
  Future<Message> sendImageMessage({
    required String conversationId,
    required String base64Image,
    String? caption,
    required bool isViewOnce,
    String? clientId,
    Duration? disappearingDuration,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      DateTime? expiresAt;
      if (disappearingDuration != null) {
        expiresAt = now.add(disappearingDuration);
      }

      // Encrypt image with AES-256-GCM locally before sending to Supabase
      final encryptedImage = await EncryptionService.instance.encryptImage(
        base64Image,
        conversationId,
      );

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'content': caption?.trim(),
        'message_type': isViewOnce ? 'view_once_image' : 'image',
        'media_data': encryptedImage,
        'created_at': now.toIso8601String(),
      };
      if (clientId != null) {
        payload['client_id'] = clientId;
      }
      if (expiresAt != null) {
        payload['expires_at'] = expiresAt.toIso8601String();
      }
      if (replyToId != null) {
        payload['media_meta'] = {
          'reply_to_id': replyToId,
          'reply_to_content': replyToContent,
          'reply_to_sender': replyToSender,
        };
      }

      final row = await _client
          .from(SupabaseConstants.messagesTable)
          .insert(payload)
          .select()
          .single();

      final serverMessage = Message.fromJson(row);
      // Return message with local unencrypted base64 for instantaneous UI display
      return serverMessage.copyWith(mediaData: base64Image);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Send a voice message with base64 encoded audio and duration.
  /// Audio payload is encrypted with AES-256-GCM locally before storage in Supabase.
  Future<Message> sendVoiceMessage({
    required String conversationId,
    required String base64Audio,
    required int durationMs,
    String? clientId,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    try {
      final now = DateTime.now().toUtc();

      // Encrypt audio payload locally before database insert
      final encryptedAudio = await EncryptionService.instance.encryptAudio(
        base64Audio,
        conversationId,
      );

      final mediaMeta = <String, dynamic>{'duration_ms': durationMs};
      if (replyToId != null) {
        mediaMeta['reply_to_id'] = replyToId;
        mediaMeta['reply_to_content'] = replyToContent;
        mediaMeta['reply_to_sender'] = replyToSender;
      }

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'message_type': 'audio',
        'media_data': encryptedAudio,
        'media_meta': mediaMeta,
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

      final serverMessage = Message.fromJson(row);
      // Return message with local unencrypted base64 for immediate UI playback
      return serverMessage.copyWith(mediaData: base64Audio);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Send a video message with base64 encoded video.
  /// Video payload is encrypted with AES-256-GCM locally before storage in Supabase.
  Future<Message> sendVideoMessage({
    required String conversationId,
    required String base64Video,
    String? caption,
    String? clientId,
    Duration? disappearingDuration,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      DateTime? expiresAt;
      if (disappearingDuration != null) {
        expiresAt = now.add(disappearingDuration);
      }

      final encryptedVideo = await EncryptionService.instance.encryptVideo(
        base64Video,
        conversationId,
      );

      final mediaMeta = <String, dynamic>{'is_video': true};
      if (replyToId != null) {
        mediaMeta['reply_to_id'] = replyToId;
        mediaMeta['reply_to_content'] = replyToContent;
        mediaMeta['reply_to_sender'] = replyToSender;
      }

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'content': caption?.trim(),
        'message_type': 'image',
        'media_data': encryptedVideo,
        'media_meta': mediaMeta,
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
      return serverMessage.copyWith(mediaData: base64Video);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Send a document message.
  /// Payload is encrypted with AES-256-GCM locally before storage in Supabase.
  Future<Message> sendDocumentMessage({
    required String conversationId,
    required String base64Document,
    required String fileName,
    required int fileSize,
    String? mimeType,
    String? clientId,
    Duration? disappearingDuration,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      DateTime? expiresAt;
      if (disappearingDuration != null) {
        expiresAt = now.add(disappearingDuration);
      }

      // Encrypt document payload with AES-256-GCM locally before sending
      final encryptedDoc = await EncryptionService.instance.encryptImage(
        base64Document,
        conversationId,
      );

      final mediaMeta = <String, dynamic>{
        'is_document': true,
        'file_name': fileName,
        'file_size': fileSize,
      };
      if (mimeType != null) mediaMeta['mime_type'] = mimeType;
      if (replyToId != null) mediaMeta['reply_to_id'] = replyToId;
      if (replyToContent != null) mediaMeta['reply_to_content'] = replyToContent;
      if (replyToSender != null) mediaMeta['reply_to_sender'] = replyToSender;

      final payload = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'content': fileName,
        'message_type': 'image', // Compatible with DB constraints; is_document meta distinguishes it
        'media_data': encryptedDoc,
        'media_meta': mediaMeta,
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
      return serverMessage.copyWith(mediaData: base64Document);
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
