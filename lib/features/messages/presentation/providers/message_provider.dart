import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/message_repository.dart';
import '../../domain/models/message.dart';
import 'notification_provider.dart';

/// Provider for the [MessageRepository].
final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MessageRepository(client);
});

/// State of messages for a single conversation.
/// Handles initial fetch, realtime sync, optimistic sending, and read receipts.
final conversationMessagesProvider = StateNotifierProvider.autoDispose
    .family<MessagesNotifier, AsyncValue<List<Message>>, String>((
      ref,
      conversationId,
    ) {
      Future.microtask(() {
        try {
          ref.read(activeConversationIdProvider.notifier).state =
              conversationId;
        } catch (_) {}
      });
      ref.onDispose(() {
        if (ref.read(activeConversationIdProvider) == conversationId) {
          ref.read(activeConversationIdProvider.notifier).state = null;
        }
      });

      final repo = ref.watch(messageRepositoryProvider);
      final client = ref.watch(supabaseClientProvider);
      return MessagesNotifier(repo, client, conversationId);
    });

class MessagesNotifier extends StateNotifier<AsyncValue<List<Message>>> {
  MessagesNotifier(this._repo, this._client, this._conversationId)
    : super(const AsyncLoading()) {
    _loadMessages();
    _subscribeRealtime();
  }

  final MessageRepository _repo;
  final SupabaseClient _client;
  final String _conversationId;
  RealtimeChannel? _channel;
  static const _uuid = Uuid();
  DateTime? _clearedAt;

  String get _currentUserId => _client.auth.currentUser!.id;

  Future<void> _loadMessages() async {
    try {
      final fetchResult = await _repo.getMessages(_conversationId);
      _clearedAt = fetchResult.clearedAt;
      final messages = fetchResult.messages;
      final prefs = await SharedPreferences.getInstance();

      // Ensure view-once images already viewed locally have mediaData stripped client-side
      final adjusted = messages.map((m) {
        if (m.isViewOnce) {
          final isViewedLocally =
              prefs.getBool('viewed_once_${m.id}_$_currentUserId') ?? false;
          if (isViewedLocally || m.viewedAt != null) {
            return m.copyWith(
              mediaData: null,
              viewedAt: m.viewedAt ?? DateTime.now().toUtc(),
            );
          }
        }
        return m;
      }).toList();

      state = AsyncData(adjusted);
      // Auto-mark unread incoming messages as read.
      unawaited(_repo.markMessagesAsRead(_conversationId));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void _subscribeRealtime() {
    _channel = _repo.subscribeToMessages(
      conversationId: _conversationId,
      onInsert: (newMessage) async {
        final currentMessages = state.valueOrNull ?? [];

        // Check if this incoming message matches an optimistic message by clientId
        final indexByClient = newMessage.clientId != null
            ? currentMessages.indexWhere(
                (m) =>
                    (m.clientId != null && m.clientId == newMessage.clientId) ||
                    m.id == newMessage.clientId,
              )
            : -1;

        if (indexByClient != -1) {
          final updated = List<Message>.from(currentMessages);
          updated[indexByClient] = newMessage;
          state = AsyncData(updated);
        } else if (!currentMessages.any((m) => m.id == newMessage.id)) {
          final isAfterClear =
              _clearedAt == null ||
              newMessage.createdAt.isAfter(_clearedAt!) ||
              newMessage.senderId == _currentUserId;

          if (isAfterClear) {
            // Prepend newest message (list is sorted newest first)
            state = AsyncData([newMessage, ...currentMessages]);
          }

          // If message is from the other user, mark as read
          if (newMessage.senderId != _currentUserId) {
            unawaited(_repo.markMessagesAsRead(_conversationId));
          }
        }
      },
      onChatCleared: (clearedAt) {
        if (_clearedAt != null && !clearedAt.isAfter(_clearedAt!)) {
          return;
        }
        _clearedAt = clearedAt;
        final currentMessages = state.valueOrNull ?? [];
        state = AsyncData(
          currentMessages.where((m) => m.createdAt.isAfter(clearedAt)).toList(),
        );
      },
      onUpdate: (updatedMessage) {
        final currentMessages = state.valueOrNull ?? [];
        final index = currentMessages.indexWhere(
          (m) => m.id == updatedMessage.id,
        );
        if (index != -1) {
          final existingMessage = currentMessages[index];

          // If the updated record from PostgreSQL logical replication omitted unchanged TOAST columns
          // (such as media_data or media_meta), preserve them from the existing in-memory message
          // UNLESS the message was explicitly marked as viewed/burned (viewedAt != null) or deleted.
          final effectiveMediaData =
              (updatedMessage.mediaData == null &&
                  updatedMessage.viewedAt == null &&
                  !updatedMessage.isDeleted)
              ? existingMessage.mediaData
              : updatedMessage.mediaData;

          final effectiveMediaMeta =
              (updatedMessage.mediaMeta == null &&
                  updatedMessage.viewedAt == null &&
                  !updatedMessage.isDeleted)
              ? existingMessage.mediaMeta
              : updatedMessage.mediaMeta;

          final merged = updatedMessage.copyWith(
            mediaData: effectiveMediaData,
            mediaMeta: effectiveMediaMeta,
          );

          final updated = List<Message>.from(currentMessages);
          updated[index] = merged;
          state = AsyncData(updated);
        }
      },
    );
  }

  /// Optimistically adds a message, sends it to Supabase, and updates status.
  Future<void> sendMessage(
    String text, {
    Duration? disappearingDuration,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final clientId = _uuid.v4();
    final optimisticMessage = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      content: trimmed,
      clientId: clientId,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.sending,
    );

    // Add optimistic message to the top of list
    final previousList = state.valueOrNull ?? [];
    state = AsyncData([optimisticMessage, ...previousList]);

    try {
      final confirmed = await _repo.sendMessage(
        conversationId: _conversationId,
        content: trimmed,
        clientId: clientId,
        disappearingDuration: disappearingDuration,
      );

      // Replace optimistic message with confirmed server message
      final currentList = state.valueOrNull ?? [];
      final idx = currentList.indexWhere(
        (m) =>
            (m.clientId != null && m.clientId == clientId) ||
            m.id == clientId ||
            m.id == confirmed.id,
      );
      if (idx != -1) {
        final updated = List<Message>.from(currentList);
        updated[idx] = confirmed;
        state = AsyncData(updated);
      }
    } catch (e) {
      // Mark optimistic message as failed
      final currentList = state.valueOrNull ?? [];
      final idx = currentList.indexWhere(
        (m) =>
            (m.clientId != null && m.clientId == clientId) || m.id == clientId,
      );
      if (idx != -1) {
        final updated = List<Message>.from(currentList);
        updated[idx] = updated[idx].copyWith(status: MessageStatus.failed);
        state = AsyncData(updated);
      }
    }
  }

  /// Soft-delete a message.
  Future<void> deleteMessage(String messageId) async {
    await _repo.deleteMessage(messageId);
  }

  /// Manually trigger mark as read.
  Future<void> markAsRead() async {
    await _repo.markMessagesAsRead(_conversationId);
  }

  /// Optimistically adds an image message, sends it, and updates state.
  Future<void> sendImageMessage({
    required String base64Image,
    String? caption,
    required bool isViewOnce,
    Duration? disappearingDuration,
  }) async {
    final clientId = _uuid.v4();
    final optimisticMessage = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      content: caption?.trim(),
      messageType: isViewOnce ? MessageType.viewOnceImage : MessageType.image,
      mediaData: base64Image,
      clientId: clientId,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.sending,
    );

    final previousList = state.valueOrNull ?? [];
    state = AsyncData([optimisticMessage, ...previousList]);

    try {
      final confirmed = await _repo.sendImageMessage(
        conversationId: _conversationId,
        base64Image: base64Image,
        caption: caption,
        isViewOnce: isViewOnce,
        clientId: clientId,
        disappearingDuration: disappearingDuration,
      );

      final currentList = state.valueOrNull ?? [];
      final idx = currentList.indexWhere(
        (m) =>
            (m.clientId != null && m.clientId == clientId) ||
            m.id == clientId ||
            m.id == confirmed.id,
      );
      if (idx != -1) {
        final updated = List<Message>.from(currentList);
        updated[idx] = confirmed;
        state = AsyncData(updated);
      }
    } catch (e) {
      final currentList = state.valueOrNull ?? [];
      final idx = currentList.indexWhere(
        (m) =>
            (m.clientId != null && m.clientId == clientId) || m.id == clientId,
      );
      if (idx != -1) {
        final updated = List<Message>.from(currentList);
        updated[idx] = updated[idx].copyWith(status: MessageStatus.failed);
        state = AsyncData(updated);
      }
    }
  }

  /// Optimistically adds a voice message, sends it, and updates state.
  Future<void> sendVoiceMessage({
    required String base64Audio,
    required int durationMs,
  }) async {
    final clientId = _uuid.v4();
    final optimisticMessage = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      messageType: MessageType.audio,
      mediaData: base64Audio,
      mediaMeta: {'duration_ms': durationMs},
      clientId: clientId,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.sending,
    );

    final previousList = state.valueOrNull ?? [];
    state = AsyncData([optimisticMessage, ...previousList]);

    try {
      final confirmed = await _repo.sendVoiceMessage(
        conversationId: _conversationId,
        base64Audio: base64Audio,
        durationMs: durationMs,
        clientId: clientId,
      );

      final currentList = state.valueOrNull ?? [];
      final idx = currentList.indexWhere(
        (m) =>
            (m.clientId != null && m.clientId == clientId) ||
            m.id == clientId ||
            m.id == confirmed.id,
      );
      if (idx != -1) {
        final updated = List<Message>.from(currentList);
        updated[idx] = confirmed;
        state = AsyncData(updated);
      }
    } catch (e) {
      final currentList = state.valueOrNull ?? [];
      final idx = currentList.indexWhere(
        (m) =>
            (m.clientId != null && m.clientId == clientId) || m.id == clientId,
      );
      if (idx != -1) {
        final updated = List<Message>.from(currentList);
        updated[idx] = updated[idx].copyWith(status: MessageStatus.failed);
        state = AsyncData(updated);
      }
    }
  }

  /// Mark view once opened and wipe media_data client-side only.
  Future<void> markViewOnceOpened(String messageId) async {
    // 1. Wipe mediaData locally from memory
    final currentList = state.valueOrNull ?? [];
    final idx = currentList.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final updated = List<Message>.from(currentList);
      updated[idx] = updated[idx].copyWith(
        mediaData: null,
        viewedAt: DateTime.now().toUtc(),
      );
      state = AsyncData(updated);
    }

    // 2. Persist viewed status on device so client never reloads it
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('viewed_once_${messageId}_$_currentUserId', true);

    // 3. Mark viewed timestamp in database (media_data remains stored in database)
    await _repo.markViewOnceOpened(messageId);
  }

  /// Clear conversation on both participants' screens without deleting rows from the database server.
  Future<void> clearChat() async {
    final now = DateTime.now().toUtc();
    _clearedAt = now;
    state = const AsyncData([]);
    await _repo.clearConversation(_conversationId, _channel);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}
