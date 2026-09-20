import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/client_chat_deletion_service.dart';
import '../../../../core/services/encryption_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/message_repository.dart';
import '../../domain/models/message.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import 'notification_provider.dart';

/// Provider for the [MessageRepository].
final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MessageRepository(client);
});

/// Quoted message information for replies.
class ReplyMessageInfo {
  const ReplyMessageInfo({
    required this.id,
    required this.content,
    required this.senderName,
  });

  final String id;
  final String content;
  final String senderName;
}

/// Active message being replied to in a specific conversation.
final activeReplyProvider = StateProvider.autoDispose
    .family<ReplyMessageInfo?, String>((ref, conversationId) => null);

/// Indicates whether the other participant in a conversation is currently typing.
final otherUserTypingProvider = StateProvider.autoDispose
    .family<bool, String>((ref, conversationId) => false);

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
        ref.invalidate(conversationsProvider);
      });

      final repo = ref.watch(messageRepositoryProvider);
      final client = ref.watch(supabaseClientProvider);
      return MessagesNotifier(ref, repo, client, conversationId);
    });

class MessagesNotifier extends StateNotifier<AsyncValue<List<Message>>> {
  MessagesNotifier(this._ref, this._repo, this._client, this._conversationId)
    : super(const AsyncLoading()) {
    _loadMessages();
    _subscribeRealtime();
    _listenToLifecycle();
  }

  final Ref _ref;
  final MessageRepository _repo;
  final SupabaseClient _client;
  final String _conversationId;
  RealtimeChannel? _channel;
  static const _uuid = Uuid();
  DateTime? _clearedAt;
  DateTime? _clientDeletedAt;
  bool _hasMore = true;
  bool _isLoadingOlder = false;
  Timer? _typingTimer;
  DateTime? _lastTypingSent;
  ProviderSubscription<bool>? _lifecycleSub;

  bool get hasMore => _hasMore;
  bool get isLoadingOlder => _isLoadingOlder;

  String get _currentUserId => _client.auth.currentUser!.id;

  void _listenToLifecycle() {
    _lifecycleSub = _ref.listen<bool>(isAppResumedProvider, (previous, isResumed) {
      if (isResumed && previous != true) {
        unawaited(syncLatestMessages());
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      if (_client.auth.currentUser != null) {
        _clientDeletedAt = await ClientChatDeletionService.instance
            .getDeletionTimestamp(
              userId: _currentUserId,
              conversationId: _conversationId,
            );
      }

      final fetchResult = await _repo.getMessages(_conversationId);
      _clearedAt = fetchResult.clearedAt;
      final messages = fetchResult.messages;
      final filteredMessages = _clientDeletedAt == null
          ? messages
          : messages
              .where((m) => m.createdAt.toUtc().isAfter(_clientDeletedAt!.toUtc()))
              .toList();

      final prefs = await SharedPreferences.getInstance();

      // Ensure view-once images already viewed locally have mediaData stripped client-side
      final adjusted = filteredMessages.map((m) {
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
      // Auto-mark unread incoming messages as read only when actively viewing in resumed state
      final isResumed = _ref.read(isAppResumedProvider);
      final activeConv = _ref.read(activeConversationIdProvider);
      if (isResumed && (activeConv == _conversationId || activeConv == null)) {
        unawaited(
          _repo.markMessagesAsRead(_conversationId).then((_) {
            try {
              _ref
                  .read(locallyReadConversationIdsProvider.notifier)
                  .update((s) => {...s, _conversationId});
            } catch (_) {}
          }),
        );
      }
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Syncs newly arrived messages from server when reopening/resuming the app
  /// or when recovering connection.
  Future<void> syncLatestMessages() async {
    try {
      final fetchResult = await _repo.getMessages(_conversationId, limit: 40);
      _clearedAt = fetchResult.clearedAt;
      final serverMessages = fetchResult.messages;
      final currentList = state.valueOrNull ?? [];

      if (currentList.isEmpty) {
        state = AsyncData(serverMessages);
      } else {
        final existingIds = <String>{};
        for (final m in currentList) {
          existingIds.add(m.id);
          if (m.clientId != null) existingIds.add(m.clientId!);
        }

        final newMessages = <Message>[];
        for (final m in serverMessages) {
          if (!existingIds.contains(m.id) &&
              (m.clientId == null || !existingIds.contains(m.clientId))) {
            final isAfterClear = _clearedAt == null ||
                m.createdAt.isAfter(_clearedAt!) ||
                m.senderId == _currentUserId;
            if (isAfterClear) {
              newMessages.add(m);
            }
          }
        }

        if (newMessages.isNotEmpty) {
          final merged = [...newMessages, ...currentList];
          merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          state = AsyncData(merged);
        }
      }

      // Mark incoming messages as read if currently resumed and viewing this chat
      final isResumed = _ref.read(isAppResumedProvider);
      final activeConv = _ref.read(activeConversationIdProvider);
      if (isResumed && (activeConv == _conversationId || activeConv == null)) {
        unawaited(
          _repo.markMessagesAsRead(_conversationId).then((_) {
            try {
              _ref
                  .read(locallyReadConversationIdsProvider.notifier)
                  .update((s) => {...s, _conversationId});
            } catch (_) {}
          }),
        );
      }
    } catch (e) {
      debugPrint('[MessagesNotifier] syncLatestMessages error: $e');
    }
  }

  /// Injects an incoming message record directly into the message list
  /// (e.g. delivered via global notifications channel or background polling)
  Future<void> insertIncomingRecord(Map<String, dynamic> record) async {
    try {
      final currentMessages = state.valueOrNull ?? [];
      final id = record['id'] as String?;
      final clientId = record['client_id'] as String?;
      if (id == null) return;

      if (currentMessages.any(
        (m) => m.id == id || (clientId != null && m.clientId == clientId),
      )) {
        return;
      }

      var msg = Message.fromJson(record);
      msg = await _repo.decryptMessagePayload(msg, _conversationId);

      final isAfterClear = _clearedAt == null ||
          msg.createdAt.isAfter(_clearedAt!) ||
          msg.senderId == _currentUserId;

      if (isAfterClear) {
        state = AsyncData([msg, ...currentMessages]);
      }

      final isResumed = _ref.read(isAppResumedProvider);
      final activeConv = _ref.read(activeConversationIdProvider);
      if (isResumed &&
          activeConv == _conversationId &&
          msg.senderId != _currentUserId) {
        unawaited(
          _repo.markMessagesAsRead(_conversationId).then((_) {
            try {
              _ref
                  .read(locallyReadConversationIdsProvider.notifier)
                  .update((s) => {...s, _conversationId});
            } catch (_) {}
          }),
        );
      }
    } catch (e) {
      debugPrint('[MessagesNotifier] insertIncomingRecord error: $e');
    }
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();
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
          final isAfterClientDelete = _clientDeletedAt == null ||
              newMessage.createdAt.toUtc().isAfter(_clientDeletedAt!.toUtc()) ||
              newMessage.senderId == _currentUserId;
          final isAfterClear = (_clearedAt == null ||
                  newMessage.createdAt.isAfter(_clearedAt!) ||
                  newMessage.senderId == _currentUserId) &&
              isAfterClientDelete;

          if (isAfterClear) {
            // Prepend newest message (list is sorted newest first)
            state = AsyncData([newMessage, ...currentMessages]);
          }

          // If message is from the other user, only mark as read if resumed AND viewing this chat
          if (newMessage.senderId != _currentUserId) {
            final isResumed = _ref.read(isAppResumedProvider);
            final activeConv = _ref.read(activeConversationIdProvider);
            if (isResumed && activeConv == _conversationId) {
              unawaited(
                _repo.markMessagesAsRead(_conversationId).then((_) {
                  try {
                    _ref
                        .read(locallyReadConversationIdsProvider.notifier)
                        .update((s) => {...s, _conversationId});
                  } catch (_) {}
                }),
              );
            }
          }
        }
      },
      onDirectMessageBroadcast: (broadcastMsg) {
        final currentMessages = state.valueOrNull ?? [];
        if (broadcastMsg.senderId == _currentUserId) return;

        final alreadyExists = currentMessages.any(
          (m) =>
              m.id == broadcastMsg.id ||
              (broadcastMsg.clientId != null &&
                  (m.clientId == broadcastMsg.clientId ||
                      m.id == broadcastMsg.clientId)),
        );
        if (alreadyExists) return;

        final isAfterClientDelete = _clientDeletedAt == null ||
            broadcastMsg.createdAt.toUtc().isAfter(_clientDeletedAt!.toUtc()) ||
            broadcastMsg.senderId == _currentUserId;
        final isAfterClear = (_clearedAt == null ||
                broadcastMsg.createdAt.isAfter(_clearedAt!) ||
                broadcastMsg.senderId == _currentUserId) &&
            isAfterClientDelete;

        if (isAfterClear) {
          state = AsyncData([broadcastMsg, ...currentMessages]);
        }

        final isResumed = _ref.read(isAppResumedProvider);
        final activeConv = _ref.read(activeConversationIdProvider);
        if (isResumed && activeConv == _conversationId) {
          unawaited(
            _repo.markMessagesAsRead(_conversationId).then((_) {
              try {
                _ref
                    .read(locallyReadConversationIdsProvider.notifier)
                    .update((s) => {...s, _conversationId});
              } catch (_) {}
            }),
          );
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
      onTyping: (senderId) {
        if (senderId != _currentUserId) {
          _ref.read(otherUserTypingProvider(_conversationId).notifier).state =
              true;
          _typingTimer?.cancel();
          _typingTimer = Timer(const Duration(seconds: 3), () {
            try {
              _ref.read(otherUserTypingProvider(_conversationId).notifier).state =
                  false;
            } catch (_) {}
          });
        }
      },
    );
  }

  /// Broadcast typing event to conversation channel.
  void sendTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!).inMilliseconds < 1800) {
      return;
    }
    _lastTypingSent = now;
    _repo.sendTyping(_channel);
  }

  /// Load historical/older messages when scrolling upwards.
  Future<void> loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMore) return;
    final currentMessages = state.valueOrNull ?? [];
    if (currentMessages.isEmpty) return;

    _isLoadingOlder = true;
    try {
      final oldestMessage = currentMessages.last;
      final result = await _repo.getMessages(
        _conversationId,
        before: oldestMessage.createdAt,
        limit: 30,
      );

      final older = result.messages;
      if (older.isEmpty || older.length < 30) {
        _hasMore = false;
      }

      final existingIds = currentMessages.map((m) => m.id).toSet();
      final freshOlder =
          older.where((m) => !existingIds.contains(m.id)).toList();

      if (freshOlder.isNotEmpty) {
        state = AsyncData([...currentMessages, ...freshOlder]);
      }
    } catch (_) {
      // Non-fatal pagination failure
    } finally {
      _isLoadingOlder = false;
    }
  }

  /// Optimistically adds a message, sends it to Supabase, and updates status.
  Future<void> sendMessage(
    String text, {
    Duration? disappearingDuration,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final clientId = _uuid.v4();
    final Map<String, dynamic>? meta = replyToId != null
        ? {
            'reply_to_id': replyToId,
            'reply_to_content': replyToContent,
            'reply_to_sender': replyToSender,
          }
        : null;

    final optimisticMessage = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      content: trimmed,
      clientId: clientId,
      mediaMeta: meta,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.sending,
    );

    // Add optimistic message to the top of list
    final previousList = state.valueOrNull ?? [];
    state = AsyncData([optimisticMessage, ...previousList]);

    // Concurrently broadcast message over WebSocket for < 50ms delivery
    unawaited(() async {
      try {
        final encrypted = await EncryptionService.instance.encryptText(
          trimmed,
          _conversationId,
        );
        final broadcastPayload = <String, dynamic>{
          'id': clientId,
          'conversation_id': _conversationId,
          'sender_id': _currentUserId,
          'content': encrypted,
          'message_type': 'text',
          'client_id': clientId,
          'created_at': optimisticMessage.createdAt.toIso8601String(),
          'media_meta': ?meta,
        };
        await _repo.broadcastDirectMessage(
          channel: _channel,
          payload: broadcastPayload,
        );
      } catch (_) {}
    }());

    try {
      final confirmed = await _repo.sendMessage(
        conversationId: _conversationId,
        content: trimmed,
        clientId: clientId,
        disappearingDuration: disappearingDuration,
        replyToId: replyToId,
        replyToContent: replyToContent,
        replyToSender: replyToSender,
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



  /// Optimistically adds an image message, sends it, and updates state.
  Future<void> sendImageMessage({
    required String base64Image,
    String? caption,
    required bool isViewOnce,
    Duration? disappearingDuration,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    final clientId = _uuid.v4();
    final Map<String, dynamic>? meta = replyToId != null
        ? {
            'reply_to_id': replyToId,
            'reply_to_content': replyToContent,
            'reply_to_sender': replyToSender,
          }
        : null;

    final optimisticMessage = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      content: caption?.trim(),
      messageType: isViewOnce ? MessageType.viewOnceImage : MessageType.image,
      mediaData: base64Image,
      mediaMeta: meta,
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
        replyToId: replyToId,
        replyToContent: replyToContent,
        replyToSender: replyToSender,
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
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    final clientId = _uuid.v4();
    final meta = <String, dynamic>{'duration_ms': durationMs};
    if (replyToId != null) {
      meta['reply_to_id'] = replyToId;
      meta['reply_to_content'] = replyToContent;
      meta['reply_to_sender'] = replyToSender;
    }

    final optimisticMessage = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      messageType: MessageType.audio,
      mediaData: base64Audio,
      mediaMeta: meta,
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
        replyToId: replyToId,
        replyToContent: replyToContent,
        replyToSender: replyToSender,
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

  /// Optimistically adds a document message, sends it, and updates state.
  Future<void> sendDocumentMessage({
    required String base64Document,
    required String fileName,
    required int fileSize,
    String? mimeType,
    Duration? disappearingDuration,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    final clientId = _uuid.v4();
    final mediaMeta = <String, dynamic>{
      'is_document': true,
      'file_name': fileName,
      'file_size': fileSize,
    };
    if (mimeType != null) mediaMeta['mime_type'] = mimeType;
    if (replyToId != null) mediaMeta['reply_to_id'] = replyToId;
    if (replyToContent != null) mediaMeta['reply_to_content'] = replyToContent;
    if (replyToSender != null) mediaMeta['reply_to_sender'] = replyToSender;

    final optimisticMessage = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      content: fileName,
      messageType: MessageType.document,
      mediaData: base64Document,
      mediaMeta: mediaMeta,
      clientId: clientId,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.sending,
    );

    final previousList = state.valueOrNull ?? [];
    state = AsyncData([optimisticMessage, ...previousList]);

    try {
      final confirmed = await _repo.sendDocumentMessage(
        conversationId: _conversationId,
        base64Document: base64Document,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        clientId: clientId,
        disappearingDuration: disappearingDuration,
        replyToId: replyToId,
        replyToContent: replyToContent,
        replyToSender: replyToSender,
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

  /// Mark view once opened: records viewed timestamp and removes client access by wiping local mediaData.
  Future<void> markViewOnceOpened(String messageId) async {
    // 1. Update viewed timestamp and strip mediaData in local state to revoke access immediately
    final currentList = state.valueOrNull ?? [];
    final idx = currentList.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final updated = List<Message>.from(currentList);
      updated[idx] = updated[idx].copyWith(
        viewedAt: DateTime.now().toUtc(),
        clearMediaData: true,
      );
      state = AsyncData(updated);
    }

    // 2. Quietly record viewed timestamp in database (server keeps media un-deleted)
    try {
      await _repo.markViewOnceOpened(messageId);
    } catch (_) {
      // Non-critical: failure to record timestamp on server does not block viewing
    }
  }

  /// Manually trigger mark as read for this conversation.
  Future<void> markAsRead() async {
    try {
      _ref
          .read(locallyReadConversationIdsProvider.notifier)
          .update((s) => {...s, _conversationId});
    } catch (_) {}
    await _repo.markMessagesAsRead(_conversationId);
  }

  /// Soft-delete a message.
  Future<void> deleteMessage(String messageId) async {
    await _repo.deleteMessage(messageId);
    final currentList = state.valueOrNull ?? [];
    state = AsyncData(currentList.where((m) => m.id != messageId).toList());
  }

  /// Clear conversation on both participants' screens without deleting rows from the database server.
  Future<void> clearChat() async {
    final now = DateTime.now().toUtc();
    _clearedAt = now;
    state = const AsyncData([]);
    await _repo.clearConversation(_conversationId, _channel);
  }

  /// Deletes this chat client-sided for the current user only.
  /// The other participant's chat and messages remain 100% untouched.
  Future<void> deleteChatForMe() async {
    final now = DateTime.now().toUtc();
    _clientDeletedAt = now;
    state = const AsyncData([]);
    EncryptionService.instance.clearKeyCache();

    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      await ClientChatDeletionService.instance.markConversationDeleted(
        userId: userId,
        conversationId: _conversationId,
        timestamp: now,
      );
    }
    try {
      _ref
          .read(locallyDeletedConversationIdsProvider.notifier)
          .update((s) => {...s, _conversationId});
      _ref.invalidate(conversationsProvider);
    } catch (_) {}
  }

  @override
  void dispose() {
    _lifecycleSub?.close();
    _typingTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}
