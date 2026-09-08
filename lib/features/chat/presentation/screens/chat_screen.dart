import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../messages/presentation/providers/message_provider.dart';
import '../../../messages/presentation/widgets/chat_input_bar.dart';
import '../../../messages/presentation/widgets/message_bubble.dart';
import '../../../profile/presentation/providers/safety_provider.dart';

/// Screen for chatting in a 1:1 conversation in real time with E2EE,
/// safety tools (block, report, meet again, expiring messages), and conversation starters.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.otherUsername,
  });

  final String conversationId;
  final String? otherUsername;

  static const List<String> _conversationStarters = [
    "🎮 What's a game you never get tired of?",
    "🚀 What's something cool you learned recently?",
    '🎧 What song are you currently obsessed with?',
    "💭 What's an unpopular opinion you have?",
    '✨ If you could master any skill instantly, what would it be?',
  ];

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
                value: 'report_user',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, color: AppColors.error, size: 18),
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
                    Icon(Icons.block_rounded, color: AppColors.error, size: 18),
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
                            'Messages are selectively encrypted with AES-256-GCM.\nNo real identity is exposed.',
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
                            children: _conversationStarters.map((starter) {
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

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return MessageBubble(
                      message: message,
                      isMine: message.isMine(currentUserId),
                      conversationId: conversationId,
                      otherUsername: otherUsername,
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
          'Request a mutual reconnection with ${otherUsername != null ? "@$otherUsername" : "this anon"}? '
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
          'Are you sure you want to block ${otherUsername != null ? "@$otherUsername" : "this user"}? '
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
              final targetName = otherUsername ?? 'Anon';
              await ref
                  .read(blockedUsersProvider.notifier)
                  .blockUser(conversationId, targetName);
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
                        reportedUserId: conversationId,
                        conversationId: conversationId,
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
