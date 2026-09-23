import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_control_service.dart';
import '../../../../core/services/presence/presence_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../domain/models/conversation.dart';
import '../providers/conversation_provider.dart';

enum ChatFilter { all, unread, active }

/// Redesigned conversations list screen with segmented filters,
/// skeleton shimmer, and layered card tiles.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key, this.onNavigateToSearch});

  final VoidCallback? onNavigateToSearch;

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  ChatFilter _activeFilter = ChatFilter.all;

  List<Conversation> _applyFilter(List<Conversation> all) {
    switch (_activeFilter) {
      case ChatFilter.all:
        return all;
      case ChatFilter.unread:
        return all.where((c) => c.unreadCount > 0).toList();
      case ChatFilter.active:
        // Filter conversations with recent messages or activity
        return all
            .where(
              (c) =>
                  c.lastMessageContent != null &&
                  c.lastMessageContent!.isNotEmpty,
            )
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final locallyReadIds = ref.watch(locallyReadConversationIdsProvider);
    final rawConversations = conversationsAsync.valueOrNull ?? [];
    final allConversations = rawConversations.map((c) {
      if (locallyReadIds.contains(c.id)) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();
    final totalUnread = allConversations.fold<int>(
      0,
      (sum, c) => sum + c.unreadCount,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await AppControlService.minimizeApp();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: AppColors.primaryGlow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'logo.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Chats',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (totalUnread > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppColors.primaryGlow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.mark_chat_unread_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$totalUnread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: 'Refresh',
              color: AppColors.textSecondaryDark,
              onPressed: () => ref.invalidate(conversationsProvider),
            ),
            IconButton(
              icon: const Icon(Icons.search_rounded, size: 22),
              tooltip: 'Search Users',
              color: AppColors.textSecondaryDark,
              onPressed:
                  widget.onNavigateToSearch ?? () => context.push('/search'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // Segmented Filter Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildFilterPill('All', ChatFilter.all),
                  const SizedBox(width: 8),
                  _buildFilterPill(
                    totalUnread > 0 ? 'Unread ($totalUnread)' : 'Unread',
                    ChatFilter.unread,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterPill('Active', ChatFilter.active),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Conversation List Body
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceDark,
                onRefresh: () async {
                  ref.invalidate(conversationsProvider);
                  await ref.read(conversationsProvider.future);
                },
                child: conversationsAsync.when(
                  loading: () => const ConversationSkeletonList(itemCount: 8),
                  error: (error, _) => _buildErrorView(error),
                  data: (allConversations) {
                    final filtered = _applyFilter(allConversations);

                    if (filtered.isEmpty) {
                      return _EmptyConversationsView(
                        filter: _activeFilter,
                        onStartChat:
                            widget.onNavigateToSearch ??
                            () => context.push('/search'),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final conv = filtered[index];
                        return _ConversationTile(
                          conversation: conv,
                          index: index,
                          onTap: () async {
                            final username = conv.otherMemberUsername ?? '';
                            final otherUid = conv.otherMemberId ?? '';
                            ref
                                .read(
                                  locallyReadConversationIdsProvider.notifier,
                                )
                                .update((s) => {...s, conv.id});
                            await context.push(
                              '/chat/${conv.id}?username=$username&otherUserId=$otherUid',
                            );
                            ref.invalidate(conversationsProvider);
                          },
                          onToggleMute: () async {
                            final repo = ref.read(
                              conversationRepositoryProvider,
                            );
                            await repo.toggleMute(
                              conv.id,
                              muted: !conv.isMuted,
                            );
                            ref.invalidate(conversationsProvider);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String title, ChatFilter filter) {
    final isSelected = _activeFilter == filter;

    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withAlpha(40)
              : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
            width: 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? AppColors.primaryLight
                : AppColors.textSecondaryDark,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(Object error) {
    debugPrint('[ConversationsScreen] Error loading chats: $error');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load chats',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMutedDark, fontSize: 13),
            ),
            const SizedBox(height: 20),
            AppButton(
              text: 'Retry',
              icon: Icons.refresh_rounded,
              width: 140,
              height: 42,
              onPressed: () => ref.invalidate(conversationsProvider),
            ),
          ],
        ),
      ),
    );
  }
}

/// Polished conversation list item tile.
class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({
    required this.conversation,
    required this.index,
    required this.onTap,
    required this.onToggleMute,
  });

  final Conversation conversation;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = conversation.otherMemberUsername ?? 'Anonymous';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final hasUnread = conversation.unreadCount > 0;
    final isOtherOnline =
        conversation.otherMemberId != null &&
        ref.watch(isUserOnlineProvider(conversation.otherMemberId));

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 250 + (index * 40).clamp(0, 300)),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) => Opacity(
        opacity: val,
        child: Transform.translate(
          offset: Offset(0, 16 * (1.0 - val)),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: hasUnread
              ? AppColors.surfaceVariantDark.withAlpha(160)
              : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasUnread
                ? AppColors.primary.withAlpha(80)
                : AppColors.surfaceBorder,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: () => _confirmDeleteChat(context, ref),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Avatar with gradient border
                  Stack(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.accentGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(40),
                              blurRadius: 8,
                            ),
                          ],
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
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 12,
                          height: 12,
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
                                      blurRadius: 5,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // Middle details (Username & Last Message)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '@$username',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: AppColors.textPrimaryDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (conversation.isMuted) ...[
                              const Icon(
                                Icons.volume_off_rounded,
                                size: 14,
                                color: AppColors.textMutedDark,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              conversation.updatedAt.chatTimestamp,
                              style: TextStyle(
                                fontSize: 11,
                                color: hasUnread
                                    ? AppColors.primaryLight
                                    : AppColors.textMutedDark,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                conversation.lastMessageContent ??
                                    'No messages yet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: hasUnread
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textMutedDark,
                                  fontWeight: hasUnread
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                  fontStyle:
                                      conversation.lastMessageContent == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ),
                            if (hasUnread) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: AppColors.primaryGlow,
                                ),
                                child: Text(
                                  '${conversation.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Popup options
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: AppColors.textMutedDark,
                    ),
                    color: AppColors.surfaceDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(
                        color: AppColors.surfaceBorder,
                        width: 1,
                      ),
                    ),
                    onSelected: (value) {
                      if (value == 'mute') {
                        onToggleMute();
                      } else if (value == 'delete') {
                        _confirmDeleteChat(context, ref);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'mute',
                        child: Row(
                          children: [
                            Icon(
                              conversation.isMuted
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              size: 18,
                              color: AppColors.textPrimaryDark,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              conversation.isMuted ? 'Unmute' : 'Mute',
                              style: const TextStyle(
                                color: AppColors.textPrimaryDark,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.error,
                            ),
                            SizedBox(width: 10),
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
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteChat(BuildContext context, WidgetRef ref) {
    final username = conversation.otherMemberUsername ?? 'Anonymous';
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
            Text('Delete Chat?'),
          ],
        ),
        content: Text(
          'Delete chat with @$username from your device?\n\n'
          'This chat and its past messages will be removed from your screen only. '
          'The other person will still have their copy.',
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
              ref
                  .read(locallyDeletedConversationIdsProvider.notifier)
                  .update((s) => {...s, conversation.id});
              final repo = ref.read(conversationRepositoryProvider);
              await repo.deleteConversationClientSided(conversation.id);
              ref.invalidate(conversationsProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat deleted for you.')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// View displayed when filtered conversations are empty.
class _EmptyConversationsView extends StatelessWidget {
  const _EmptyConversationsView({
    required this.filter,
    required this.onStartChat,
  });

  final ChatFilter filter;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;
    IconData icon;

    switch (filter) {
      case ChatFilter.all:
        title = 'No conversations yet';
        subtitle =
            'Find someone interesting to talk to anonymously. Search by handle or match on shared interests!';
        icon = Icons.chat_bubble_outline_rounded;
        break;
      case ChatFilter.unread:
        title = 'No unread messages';
        subtitle = 'You are all caught up on your anonymous chats.';
        icon = Icons.mark_chat_read_outlined;
        break;
      case ChatFilter.active:
        title = 'No active conversations';
        subtitle = 'Start a fresh conversation with an anon!';
        icon = Icons.radar_rounded;
        break;
    }

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withAlpha(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(20),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(icon, size: 52, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryDark,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            if (filter == ChatFilter.all || filter == ChatFilter.active)
              AppButton(
                text: 'Find an Anon to Chat',
                icon: Icons.radar_rounded,
                width: 220,
                height: 46,
                onPressed: onStartChat,
              ),
          ],
        ),
      ),
    );
  }
}
