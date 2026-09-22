import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/presence/presence_provider.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import '../../../messages/presentation/providers/message_provider.dart';
import '../../../messages/presentation/providers/notification_provider.dart';
import '../../../messages/presentation/widgets/chat_input_bar.dart';
import '../../../messages/presentation/widgets/message_bubble.dart';
import '../../../profile/presentation/providers/safety_provider.dart';

/// Screen for chatting in a 1:1 conversation in real time with E2EE,
/// safety tools (block, report, meet again, expiring messages), live typing,
/// swipe-to-reply, historical pagination, and in-chat keyword search.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.otherUsername,
    this.otherUserId,
  });

  final String conversationId;
  final String? otherUsername;
  final String? otherUserId;

  static const List<String> _conversationStarters = [
    "🎮 What's a game you never get tired of?",
    "🚀 What's something cool you learned recently?",
    '🎧 What song are you currently obsessed with?',
    "💭 What's an unpopular opinion you have?",
    '✨ If you could master any skill instantly, what would it be?',
  ];

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _showScrollToBottom = false;
  String? _resolvedOtherUserId;

  @override
  void initState() {
    super.initState();
    _resolvedOtherUserId = widget.otherUserId;
    if (_resolvedOtherUserId == null) {
      _resolveOtherUserId();
    }
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    // Dismiss notifications for this conversation upon entering
    NotificationService.instance.clearNotificationsForConversation(
      widget.conversationId,
    );

    // Track active chat, mark unread messages as read in DB and update chats section immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activeConversationIdProvider.notifier).state =
            widget.conversationId;
        ref
            .read(locallyReadConversationIdsProvider.notifier)
            .update((s) => {...s, widget.conversationId});
        ref
            .read(conversationMessagesProvider(widget.conversationId).notifier)
            .markAsRead();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    if (ref.read(activeConversationIdProvider) == widget.conversationId) {
      ref.read(activeConversationIdProvider.notifier).state = null;
    }
    ref.invalidate(conversationsProvider);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(activeConversationIdProvider.notifier).state =
          widget.conversationId;
      ref
          .read(conversationMessagesProvider(widget.conversationId).notifier)
          .syncLatestMessages();
      ref
          .read(locallyReadConversationIdsProvider.notifier)
          .update((s) => {...s, widget.conversationId});
      NotificationService.instance.clearNotificationsForConversation(
        widget.conversationId,
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (ref.read(activeConversationIdProvider) == widget.conversationId) {
        ref.read(activeConversationIdProvider.notifier).state = null;
      }
    }
  }

  void _resolveOtherUserId() {
    final convs = ref.read(conversationsProvider).valueOrNull ?? [];
    for (final c in convs) {
      if (c.id == widget.conversationId && c.otherMemberId != null) {
        _resolvedOtherUserId = c.otherMemberId;
        return;
      }
    }

    SupabaseService.client
        .from(SupabaseConstants.conversationMembersTable)
        .select('user_id')
        .eq('conversation_id', widget.conversationId)
        .then((rows) {
          final currentUserId = SupabaseService.client.auth.currentUser?.id;
          for (final row in rows) {
            final uid = row['user_id'] as String;
            if (uid != currentUserId && mounted) {
              setState(() => _resolvedOtherUserId = uid);
              break;
            }
          }
        })
        .catchError((_) {});
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        ref
            .read(conversationMessagesProvider(widget.conversationId).notifier)
            .loadOlderMessages();
      }
      final showFab = _scrollController.offset > 300;
      if (showFab != _showScrollToBottom) {
        setState(() => _showScrollToBottom = showFab);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = SupabaseService.client.auth.currentUser?.id ?? '';
    final messagesAsync = ref.watch(
      conversationMessagesProvider(widget.conversationId),
    );
    final messagesNotifier = ref.read(
      conversationMessagesProvider(widget.conversationId).notifier,
    );
    final isOtherTyping = ref.watch(
      otherUserTypingProvider(widget.conversationId),
    );
    final activeReply = ref.watch(activeReplyProvider(widget.conversationId));
    final isOtherOnline =
        _resolvedOtherUserId != null &&
        ref.watch(isUserOnlineProvider(_resolvedOtherUserId));

    final displayTitle = widget.otherUsername != null
        ? '@${widget.otherUsername}'
        : 'Anonymous Chat';
    final initial =
        widget.otherUsername != null && widget.otherUsername!.isNotEmpty
        ? widget.otherUsername![0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: _isSearching ? 8 : 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Search messages...',
                  hintStyle: const TextStyle(
                    color: AppColors.textMutedDark,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            size: 18,
                            color: AppColors.textMutedDark,
                          ),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                ),
              )
            : Row(
                children: [
                  // Avatar with gradient border and presence badge
                  Stack(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.accentGradient,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.cardDark,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOtherOnline
                                ? AppColors.online
                                : AppColors.offline,
                            border: Border.all(
                              color: AppColors.surfaceDark,
                              width: 2,
                            ),
                            boxShadow: isOtherOnline
                                ? [
                                    BoxShadow(
                                      color: AppColors.online.withValues(
                                        alpha: 0.6,
                                      ),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isOtherTyping
                                    ? AppColors.primaryLight
                                    : (isOtherOnline
                                          ? AppColors.online
                                          : AppColors.offline),
                                shape: BoxShape.circle,
                                boxShadow: (isOtherOnline && !isOtherTyping)
                                    ? [
                                        BoxShadow(
                                          color: AppColors.online.withValues(
                                            alpha: 0.6,
                                          ),
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isOtherTyping
                                  ? 'typing...'
                                  : (isOtherOnline
                                        ? 'Online · E2EE'
                                        : 'Offline · E2EE'),
                              style: TextStyle(
                                fontSize: 11,
                                color: isOtherTyping
                                    ? AppColors.primaryLight
                                    : (isOtherOnline
                                          ? AppColors.online
                                          : AppColors.textMutedDark),
                                fontWeight: FontWeight.w500,
                                fontStyle: isOtherTyping
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textSecondaryDark,
              ),
              tooltip: 'Close search',
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });
              },
            )
          else ...[
            IconButton(
              icon: const Icon(
                Icons.search_rounded,
                color: AppColors.textSecondaryDark,
              ),
              tooltip: 'Search messages',
              onPressed: () => setState(() => _isSearching = true),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppColors.textSecondaryDark,
              ),
              tooltip: 'Chat Options',
              color: AppColors.surfaceDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(
                  color: AppColors.surfaceBorder,
                  width: 1,
                ),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'meet_again':
                    _showMeetAgainDialog(context);
                    break;
                  case 'disappearing':
                    _showDisappearingDialog(context);
                    break;
                  case 'block_user':
                    _confirmBlockUser(context, ref);
                    break;
                  case 'report_user':
                    _showReportUserDialog(context, ref);
                    break;
                  case 'clear_chat':
                    _confirmClearChat(context, messagesNotifier);
                    break;
                  case 'delete_chat':
                    _confirmDeleteChat(context, messagesNotifier);
                    break;
                  case 'security_info':
                    _showSecurityDialog(context);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'meet_again',
                  child: Row(
                    children: [
                      Icon(
                        Icons.handshake_outlined,
                        color: AppColors.secondary,
                        size: 18,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Meet Again',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'disappearing',
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        color: AppColors.primaryLight,
                        size: 18,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Disappearing Messages',
                        style: TextStyle(
                          color: AppColors.textPrimaryDark,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete_chat',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Delete Chat',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear_chat',
                  child: Row(
                    children: [
                      Icon(
                        Icons.cleaning_services_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Clear Chat (Both)',
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'report_user',
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        color: AppColors.error,
                        size: 18,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Report User',
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'block_user',
                  child: Row(
                    children: [
                      Icon(
                        Icons.block_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Block User',
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'security_info',
                  child: Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: AppColors.primaryLight,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Anonymity Info',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Failed to load messages',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMutedDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              data: (messages) {
                final query = _searchController.text.trim().toLowerCase();
                final displayed = query.isEmpty
                    ? messages
                    : messages.where((m) {
                        return (m.content?.toLowerCase().contains(query) ??
                                false) ||
                            (m.displayText.toLowerCase().contains(query));
                      }).toList();

                if (displayed.isEmpty) {
                  if (query.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: AppColors.textMutedDark,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No messages matching "$query"',
                            style: const TextStyle(
                              color: AppColors.textSecondaryDark,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withAlpha(22),
                            ),
                            child: const Icon(
                              Icons.lock_clock_rounded,
                              size: 38,
                              color: AppColors.primaryLight,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Say hello anonymously!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimaryDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Messages and media are end-to-end encrypted with AES-256-GCM.\nNo real identity is exposed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondaryDark,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 22),

                          // Conversation Starters
                          const Text(
                            'Conversation Starters',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: ChatScreen._conversationStarters.map((
                              starter,
                            ) {
                              return ActionChip(
                                label: Text(
                                  starter,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimaryDark,
                                  ),
                                ),
                                backgroundColor: AppColors.surfaceVariantDark,
                                side: const BorderSide(
                                  color: AppColors.surfaceBorder,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                onPressed: () {
                                  messagesNotifier.sendMessage(starter);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: displayed.length,
                      itemBuilder: (context, index) {
                        final message = displayed[index];
                        return MessageBubble(
                          message: message,
                          isMine: message.isMine(currentUserId),
                          conversationId: widget.conversationId,
                          otherUsername: widget.otherUsername,
                          onReply: (msg) {
                            ref
                                .read(
                                  activeReplyProvider(
                                    widget.conversationId,
                                  ).notifier,
                                )
                                .state = ReplyMessageInfo(
                              id: msg.id,
                              content: msg.displayText,
                              senderName: msg.isMine(currentUserId)
                                  ? 'You'
                                  : (widget.otherUsername != null
                                        ? '@${widget.otherUsername}'
                                        : 'Anon'),
                            );
                          },
                          onDelete: () =>
                              messagesNotifier.deleteMessage(message.id),
                          onViewOnceOpened: () =>
                              messagesNotifier.markViewOnceOpened(message.id),
                        );
                      },
                    ),
                    if (_showScrollToBottom)
                      Positioned(
                        bottom: 12,
                        right: 16,
                        child: FloatingActionButton.small(
                          backgroundColor: AppColors.surfaceDark,
                          foregroundColor: AppColors.primaryLight,
                          elevation: 4,
                          shape: const CircleBorder(
                            side: BorderSide(
                              color: AppColors.surfaceBorder,
                              width: 1,
                            ),
                          ),
                          onPressed: _scrollToBottom,
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // Live Typing Indicator
          if (isOtherTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.primaryLight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.otherUsername != null ? "@${widget.otherUsername}" : "Anon"} is typing...',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
            ),

          // Input bar
          ChatInputBar(
            replyMessage: activeReply,
            onCancelReply: () {
              ref
                      .read(activeReplyProvider(widget.conversationId).notifier)
                      .state =
                  null;
            },
            onTyping: () => messagesNotifier.sendTyping(),
            onSend: (text) {
              messagesNotifier.sendMessage(
                text,
                replyToId: activeReply?.id,
                replyToContent: activeReply?.content,
                replyToSender: activeReply?.senderName,
              );
              ref
                      .read(activeReplyProvider(widget.conversationId).notifier)
                      .state =
                  null;
            },
            onSendImage: (base64Img, caption, isViewOnce) {
              messagesNotifier.sendImageMessage(
                base64Image: base64Img,
                caption: caption,
                isViewOnce: isViewOnce,
                replyToId: activeReply?.id,
                replyToContent: activeReply?.content,
                replyToSender: activeReply?.senderName,
              );
              ref
                      .read(activeReplyProvider(widget.conversationId).notifier)
                      .state =
                  null;
            },
            onSendVoice: (base64Audio, durationMs) {
              messagesNotifier.sendVoiceMessage(
                base64Audio: base64Audio,
                durationMs: durationMs,
                replyToId: activeReply?.id,
                replyToContent: activeReply?.content,
                replyToSender: activeReply?.senderName,
              );
              ref
                      .read(activeReplyProvider(widget.conversationId).notifier)
                      .state =
                  null;
            },
            onSendDocument: (base64Doc, fileName, fileSize, ext) {
              messagesNotifier.sendDocumentMessage(
                base64Document: base64Doc,
                fileName: fileName,
                fileSize: fileSize,
                mimeType: ext,
                replyToId: activeReply?.id,
                replyToContent: activeReply?.content,
                replyToSender: activeReply?.senderName,
              );
              ref
                      .read(activeReplyProvider(widget.conversationId).notifier)
                      .state =
                  null;
            },
          ),
        ],
      ),
    );
  }

  void _showMeetAgainDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.handshake_outlined,
              color: AppColors.secondary,
              size: 22,
            ),
            SizedBox(width: 10),
            Text('Meet Again?'),
          ],
        ),
        content: Text(
          'Request a mutual reconnection with ${widget.otherUsername != null ? "@${widget.otherUsername}" : "this anon"}? '
          'Once connected, you can continue chatting without losing this thread.',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.textSecondaryDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.showSnackBar(
                'Reconnection requested! When accepted, you will remain connected.',
              );
            },
            child: const Text(
              'Send Request',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDisappearingDialog(BuildContext context) {
    const durations = [
      {'label': 'Off (Keep forever)', 'val': 'off'},
      {'label': '24 Hours', 'val': '24h'},
      {'label': '7 Days', 'val': '7d'},
      {'label': '30 Days', 'val': '30d'},
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disappearing Messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: durations.map((d) {
            return ListTile(
              title: Text(d['label']!, style: const TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.of(ctx).pop();
                context.showSnackBar(
                  'Disappearing timer set to ${d['label']}. Future messages will expire automatically.',
                );
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _confirmBlockUser(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: AppColors.error, size: 22),
            SizedBox(width: 10),
            Text('Block Anon?'),
          ],
        ),
        content: Text(
          'Are you sure you want to block ${widget.otherUsername != null ? "@${widget.otherUsername}" : "this user"}? '
          'They will not be able to message you or match with you again.',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.textSecondaryDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final targetName = widget.otherUsername ?? 'Anon';
              await ref
                  .read(blockedUsersProvider.notifier)
                  .blockUser(widget.conversationId, targetName);
              if (context.mounted) {
                context.showSnackBar('User blocked successfully.');
              }
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _showReportUserDialog(BuildContext context, WidgetRef ref) {
    const reasons = [
      'Harassment',
      'Spam',
      'Inappropriate Content',
      'Scam / Fraud',
      'Other',
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Anon'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a reason for reporting this user:',
              style: TextStyle(fontSize: 13, color: AppColors.textMutedDark),
            ),
            const SizedBox(height: 12),
            ...reasons.map(
              (r) => ListTile(
                dense: true,
                title: Text(r, style: const TextStyle(fontSize: 14)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final currentUid =
                      SupabaseService.client.auth.currentUser?.id ?? '';
                  await ref
                      .read(safetyRepositoryProvider)
                      .submitReport(
                        currentUserId: currentUid,
                        reportedUserId: widget.conversationId,
                        conversationId: widget.conversationId,
                        reason: r,
                        details: 'Reported from chat view',
                      );
                  if (context.mounted) {
                    context.showSnackBar(
                      'Thank you. We take safety seriously and have received your report.',
                    );
                  }
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showSecurityDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: AppColors.secondary, size: 22),
            SizedBox(width: 10),
            Text(
              'Anonymous Chat',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'In AnonApp, you are strictly pseudonymous. '
          'Messages, voice notes, and media are end-to-end encrypted with AES-256-GCM cipher.\n\n'
          'Your passwords, device details, and personal data are never exposed.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.textSecondaryDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _confirmClearChat(BuildContext context, MessagesNotifier notifier) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.cleaning_services_rounded,
              color: AppColors.error,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Clear Chat?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'All messages in this conversation will be cleared from both participants\' screens.\n\nThis cannot be undone.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.textSecondaryDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await notifier.clearChat();
              if (context.mounted) {
                context.showSnackBar('Chat cleared for both participants.');
              }
            },
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteChat(BuildContext context, MessagesNotifier notifier) {
    final username = widget.otherUsername != null
        ? '@${widget.otherUsername}'
        : 'this user';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.delete_forever_rounded,
              color: AppColors.error,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Delete Chat?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Delete chat with $username from your device?\n\n'
          'All past messages will be removed from your screen only. '
          'The other person will still keep their chat history.',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.textSecondaryDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await notifier.deleteChatForMe();
              if (context.mounted) {
                Navigator.of(context).pop();
                context.showSnackBar('Chat deleted for you.');
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
