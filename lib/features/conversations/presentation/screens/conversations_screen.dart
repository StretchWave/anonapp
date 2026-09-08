import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../domain/models/conversation.dart';
import '../providers/conversation_provider.dart';

/// Screen displaying the list of active conversations.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key, this.onNavigateToSearch});

  /// Optional callback to switch to the search tab.
  final VoidCallback? onNavigateToSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(38),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.security_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            const Text('AnonApp'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh conversations',
            onPressed: () => ref.invalidate(conversationsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: onNavigateToSearch ?? () => context.push('/search'),
        tooltip: 'New Chat',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.chat_bubble_outline_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(conversationsProvider);
          await ref.read(conversationsProvider.future);
        },
        child: conversationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load conversations',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(153),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(conversationsProvider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
          data: (conversations) {
            if (conversations.isEmpty) {
              return _EmptyConversationsView(
                onStartChat:
                    onNavigateToSearch ?? () => context.push('/search'),
              );
            }

            return ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                indent: 72,
                color: theme.colorScheme.outlineVariant.withAlpha(50),
              ),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return _ConversationTile(
                  conversation: conversation,
                  onTap: () {
                    final username = conversation.otherMemberUsername ?? '';
                    context.push('/chat/${conversation.id}?username=$username');
                  },
                  onToggleMute: () async {
                    final repo = ref.read(conversationRepositoryProvider);
                    await repo.toggleMute(
                      conversation.id,
                      muted: !conversation.isMuted,
                    );
                    ref.invalidate(conversationsProvider);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Conversation list item.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onToggleMute,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = conversation.otherMemberUsername ?? 'Anonymous';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withAlpha(38),
        child: Text(
          initial,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '@$username',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conversation.isMuted) ...[
            Icon(
              Icons.volume_off_rounded,
              size: 16,
              color: theme.colorScheme.onSurface.withAlpha(128),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            conversation.updatedAt.chatTimestamp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(128),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                conversation.lastMessageContent ?? 'No messages yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: conversation.lastMessageContent != null
                      ? theme.colorScheme.onSurface.withAlpha(179)
                      : theme.colorScheme.onSurface.withAlpha(102),
                  fontStyle: conversation.lastMessageContent == null
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
            if (conversation.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, size: 20),
        onSelected: (value) {
          if (value == 'mute') {
            onToggleMute();
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
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(conversation.isMuted ? 'Unmute' : 'Mute'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// View displayed when the user has no conversations.
class _EmptyConversationsView extends StatelessWidget {
  const _EmptyConversationsView({required this.onStartChat});

  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withAlpha(26),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Start chatting anonymously! Search for other users by username or by their 8-character contact code.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(153),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onStartChat,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Find Someone to Chat'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
