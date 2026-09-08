import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../messages/presentation/providers/message_provider.dart';
import '../../../messages/presentation/widgets/chat_input_bar.dart';
import '../../../messages/presentation/widgets/message_bubble.dart';

/// Screen for chatting in a 1:1 conversation in real time with E2EE.
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
    final initial = otherUsername != null && otherUsername!.isNotEmpty
        ? otherUsername![0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar with gradient border
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
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'End-to-End Encrypted',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w500,
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
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppColors.textSecondaryDark,
            ),
            tooltip: 'Chat Options',
            color: AppColors.surfaceDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.surfaceBorder, width: 1),
            ),
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
                      size: 18,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Clear Chat',
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
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withAlpha(22),
                            ),
                            child: const Icon(
                              Icons.lock_clock_rounded,
                              size: 42,
                              color: AppColors.primaryLight,
                            ),
                          ),
                          const SizedBox(height: 18),
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
                            'Messages are selectively encrypted with AES-256-GCM.\nNo real identity is exposed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryDark,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 10),
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

          // Input bar
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
          'Text messages are end-to-end encrypted with AES-256-GCM cipher.\n\n'
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
}
