import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../messages/presentation/providers/message_provider.dart';
import '../../../messages/presentation/widgets/chat_input_bar.dart';
import '../../../messages/presentation/widgets/message_bubble.dart';

/// Screen for chatting in a 1:1 conversation in real time.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.otherUsername,
  });

  final String conversationId;
  final String? otherUsername;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final currentUserId = SupabaseService.client.auth.currentUser?.id ?? '';
    final messagesAsync = ref.watch(
      conversationMessagesProvider(conversationId),
    );
    final messagesNotifier = ref.read(
      conversationMessagesProvider(conversationId).notifier,
    );

    final displayTitle = otherUsername != null
        ? '@$otherUsername'
        : 'Anonymous Chat';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withAlpha(38),
              child: Text(
                otherUsername != null && otherUsername!.isNotEmpty
                    ? otherUsername![0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'End-to-End Pseudonymous',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(128),
                          fontSize: 11,
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Chat Options',
            onSelected: (value) {
              if (value == 'clear_chat') {
                _confirmClearChat(context, messagesNotifier);
              } else if (value == 'security_info') {
                _showSecurityDialog(context);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'clear_chat',
                child: Row(
                  children: [
                    Icon(
                      Icons.cleaning_services_rounded,
                      color: AppColors.error,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Text('Clear Chat'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'security_info',
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Anonymity Info'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Security header banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.accent.withAlpha(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Messages are secured with Supabase Row-Level Security',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load messages',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.waving_hand_rounded,
                            size: 44,
                            color: theme.colorScheme.primary.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Say hello anonymously!',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No personal info is shared. Messages are synced in real time.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(153),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return MessageBubble(
                      message: message,
                      isMine: message.isMine(currentUserId),
                      onDelete: () =>
                          messagesNotifier.deleteMessage(message.id),
                      onViewOnceOpened: () =>
                          messagesNotifier.markViewOnceOpened(message.id),
                    );
                  },
                );
              },
            ),
          ),

          // Input bar supporting text (Enter to send), images, view-once, and voice
          ChatInputBar(
            onSend: (text) => messagesNotifier.sendMessage(text),
            onSendImage: (base64Img, caption, isViewOnce) {
              messagesNotifier.sendImageMessage(
                base64Image: base64Img,
                caption: caption,
                isViewOnce: isViewOnce,
              );
            },
            onSendVoice: (base64Audio, durationMs) {
              messagesNotifier.sendVoiceMessage(
                base64Audio: base64Audio,
                durationMs: durationMs,
              );
            },
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
            Icon(Icons.shield_outlined, color: AppColors.accent),
            SizedBox(width: 10),
            Text('Anonymous Chat'),
          ],
        ),
        content: const Text(
          'In AnonApp, you are only known by your username and contact code. '
          'Your login password, email, phone number, or real identity are never exposed.\n\n'
          'PostgreSQL Row-Level Security ensures only you and your chat partner can access these messages.',
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
            Icon(Icons.cleaning_services_rounded, color: AppColors.error),
            SizedBox(width: 10),
            Text('Clear Chat?'),
          ],
        ),
        content: const Text(
          'All messages in this conversation will be cleared from both participants\' screens.\n\n',
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
}
