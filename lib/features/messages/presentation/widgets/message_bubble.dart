import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../profile/data/bookmark_repository.dart';
import '../../../profile/presentation/providers/bookmark_provider.dart';
import '../../../profile/presentation/providers/safety_provider.dart';
import '../../domain/models/message.dart';
import 'view_once_dialog.dart';
import 'voice_player.dart';

/// Bubble displaying an individual chat message with timestamps, status ticks,
/// rich media (images, view-once photos, voice notes), and contextual bookmarking/reporting.
class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.conversationId,
    this.otherUsername,
    this.onDelete,
    this.onViewOnceOpened,
    this.onReply,
  });

  final Message message;
  final bool isMine;
  final String? conversationId;
  final String? otherUsername;
  final VoidCallback? onDelete;
  final VoidCallback? onViewOnceOpened;
  final void Function(Message)? onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;

    Widget bubbleWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3.5),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) const SizedBox(width: 4),
          Flexible(
            child: GestureDetector(
              onLongPress: !message.isDeleted
                  ? () => _showContextMenu(context, ref)
                  : null,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: context.screenSize.width * 0.78,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: message.isImage ? 4 : 14,
                  vertical: message.isImage ? 4 : 10,
                ),
                decoration: BoxDecoration(
                  gradient: isMine && message.status != MessageStatus.failed
                      ? AppColors.sentBubbleGradient
                      : null,
                  color: isMine
                      ? (message.status == MessageStatus.failed
                            ? AppColors.error.withAlpha(200)
                            : null)
                      : AppColors.surfaceVariantDark,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMine ? 18 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 18),
                  ),
                  border: Border.all(
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.12)
                        : AppColors.surfaceBorder,
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.hasReply) ...[
                      _buildQuotedReply(context),
                      const SizedBox(height: 6),
                    ],
                    _buildContent(context, theme),
                    const SizedBox(height: 3),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: message.isImage ? 8 : 0,
                        vertical: message.isImage ? 4 : 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            message.createdAt.shortTime,
                            style: TextStyle(
                              fontSize: 10,
                              color: isMine
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : AppColors.textMutedDark,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 4),
                            _buildStatusIcon(message.status),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 4),
        ],
      ),
    );

    if (!message.isDeleted && onReply != null) {
      bubbleWidget = Dismissible(
        key: Key('reply_${message.id}'),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (direction) async {
          await HapticFeedback.lightImpact();
          onReply?.call(message);
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          child: const Icon(
            Icons.reply_rounded,
            color: AppColors.primaryLight,
            size: 24,
          ),
        ),
        child: bubbleWidget,
      );
    }

    return bubbleWidget;
  }

  Widget _buildQuotedReply(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.black.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMine ? Colors.white70 : AppColors.primaryLight,
            width: 3.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.replyToSender ?? (isMine ? 'You' : 'Anon'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isMine ? Colors.white : AppColors.primaryLight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToContent ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isMine ? Colors.white70 : AppColors.textSecondaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    if (message.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block_rounded,
            size: 14,
            color: isMine
                ? Colors.white.withValues(alpha: 0.7)
                : AppColors.textMutedDark,
          ),
          const SizedBox(width: 6),
          Text(
            message.displayText,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 13,
              color: isMine
                  ? Colors.white.withValues(alpha: 0.7)
                  : AppColors.textMutedDark,
            ),
          ),
        ],
      );
    }

    // Voice Message
    if (message.isAudio) {
      if (message.mediaData == null || message.mediaData!.isEmpty) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_off_rounded,
              size: 20,
              color: isMine ? Colors.white70 : AppColors.textMutedDark,
            ),
            const SizedBox(width: 8),
            Text(
              'Voice message unavailable',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: isMine ? Colors.white70 : AppColors.textMutedDark,
              ),
            ),
          ],
        );
      }
      final durationMs = message.mediaMeta?['duration_ms'] as int?;
      return VoicePlayer(
        base64Audio: message.mediaData!,
        isMine: isMine,
        totalDurationMs: durationMs,
      );
    }

    // View-Once Photo Message
    if (message.isViewOnce) {
      final wasViewed = message.isViewOnceOpened;
      return GestureDetector(
        onTap: () {
          if (wasViewed) {
            context.showSnackBar(
              'This photo was set to view once and has already been opened.',
            );
            return;
          }
          if (isMine) {
            context.showSnackBar(
              'View-once photo sent. Waiting for recipient to open.',
            );
            return;
          }
          ViewOnceDialog.show(
            context,
            message: message,
            onClosed: () => onViewOnceOpened?.call(),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: wasViewed
                ? (isMine
                    ? Colors.black.withValues(alpha: 0.15)
                    : AppColors.surfaceVariantDark.withValues(alpha: 0.5))
                : (isMine
                    ? AppColors.accent.withValues(alpha: 0.2)
                    : AppColors.primary.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: wasViewed
                  ? (isMine
                      ? Colors.white.withValues(alpha: 0.15)
                      : AppColors.surfaceBorder)
                  : (isMine
                      ? AppColors.accent.withValues(alpha: 0.5)
                      : AppColors.primaryLight.withValues(alpha: 0.5)),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                wasViewed
                    ? Icons.lock_clock_outlined
                    : (isMine
                        ? Icons.looks_one_rounded
                        : Icons.local_fire_department_rounded),
                color: wasViewed
                    ? (isMine ? Colors.white54 : AppColors.textMutedDark)
                    : (isMine ? AppColors.accent : AppColors.primaryLight),
                size: 22,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wasViewed ? 'Photo (Opened)' : 'View-Once Photo',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: wasViewed
                          ? (isMine ? Colors.white70 : AppColors.textMutedDark)
                          : AppColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    wasViewed
                        ? (isMine
                            ? 'Opened by recipient'
                            : 'Removed • Already viewed')
                        : (isMine ? 'Sent • 1 View' : 'Tap to open'),
                    style: TextStyle(
                      fontSize: 11,
                      color: wasViewed
                          ? (isMine ? Colors.white38 : AppColors.textMutedDark)
                          : (isMine
                              ? AppColors.accent
                              : AppColors.primaryLight),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Document Message
    if (message.isDocument) {
      return _buildDocumentContent(context);
    }

    // Regular Image Message
    if (message.isImage && message.mediaData != null) {
      return _buildImageContent(context);
    }

    // Standard Text Message
    return Text(
      message.displayText,
      style: TextStyle(
        fontSize: 14.5,
        height: 1.35,
        color: isMine ? Colors.white : AppColors.textPrimaryDark,
      ),
    );
  }

  Future<void> _handleDocumentTap(BuildContext context) async {
    if (message.mediaData == null || message.mediaData!.isEmpty) {
      context.showSnackBar('Document content is unavailable.', isError: true);
      return;
    }

    try {
      final fileName = message.documentFileName ?? 'document_${message.id.substring(0, 8)}';
      var clean = message.mediaData!.trim();
      if (clean.contains(',')) clean = clean.split(',').last;
      final bytes = base64Decode(clean);

      final tempDir = await getTemporaryDirectory();
      final targetFile = File('${tempDir.path}/$fileName');
      await targetFile.writeAsBytes(bytes);

      if (context.mounted) {
        context.showSnackBar('Saved to ${targetFile.path}');
      }
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar('Error opening document: $e', isError: true);
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Document';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String? fileName) {
    if (fileName == null) return Icons.insert_drive_file_rounded;
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return Icons.folder_zip_rounded;
      case 'txt':
        return Icons.text_snippet_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String? fileName) {
    if (fileName == null) return const Color(0xFFFF9F43);
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return const Color(0xFFFF5252);
      case 'doc':
      case 'docx':
        return const Color(0xFF4A90E2);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF2ECC71);
      case 'zip':
      case 'rar':
      case '7z':
        return const Color(0xFFF39C12);
      default:
        return const Color(0xFFFF9F43);
    }
  }

  Widget _buildDocumentContent(BuildContext context) {
    final fileName = message.documentFileName ?? 'Document';
    final fileSize = message.documentFileSize;
    final fileColor = _getFileColor(fileName);
    final fileIcon = _getFileIcon(fileName);

    return InkWell(
      onTap: () => _handleDocumentTap(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withAlpha(25)
              : AppColors.surfaceVariantDark.withAlpha(180),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMine
                ? Colors.white.withAlpha(40)
                : AppColors.surfaceBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: fileColor.withAlpha(35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fileColor.withAlpha(80), width: 1.2),
              ),
              child: Icon(fileIcon, color: fileColor, size: 22),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isMine ? Colors.white : AppColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatFileSize(fileSize),
                        style: TextStyle(
                          fontSize: 11,
                          color: isMine ? Colors.white70 : AppColors.textMutedDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.download_rounded,
                        size: 13,
                        color: isMine ? Colors.white60 : AppColors.textMutedDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    try {
      final bytes = base64Decode(message.mediaData!);
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: GestureDetector(
          onTap: () => _showFullScreenImage(context, bytes),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 240),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildCorruptPlaceholder(),
            ),
          ),
        ),
      );
    } catch (_) {
      return _buildCorruptPlaceholder();
    }
  }

  Widget _buildCorruptPlaceholder() {
    return Container(
      width: 180,
      height: 100,
      color: Colors.black26,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_rounded, size: 28, color: Colors.white54),
          SizedBox(height: 6),
          Text(
            'Failed to load media',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded, size: 13, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(
          Icons.done_all_rounded,
          size: 13,
          color: Colors.white70,
        );
      case MessageStatus.read:
        return const Icon(
          Icons.done_all_rounded,
          size: 13,
          color: AppColors.secondary,
        );
      case MessageStatus.failed:
        return const Icon(
          Icons.error_outline_rounded,
          size: 13,
          color: Colors.white,
        );
    }
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final isBookmarked =
        ref.watch(isMessageBookmarkedProvider(message.id)).valueOrNull ?? false;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReply != null && !message.isDeleted)
                ListTile(
                  leading: const Icon(
                    Icons.reply_rounded,
                    color: AppColors.primaryLight,
                  ),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onReply?.call(message);
                  },
                ),
              if (message.content != null && message.content!.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(
                    Icons.copy_rounded,
                    color: AppColors.primaryLight,
                  ),
                  title: const Text('Copy Message'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Clipboard.setData(ClipboardData(text: message.content!));
                    context.showSnackBar('Message copied to clipboard');
                  },
                ),
                ListTile(
                  leading: Icon(
                    isBookmarked
                        ? Icons.bookmark_remove_rounded
                        : Icons.bookmark_add_outlined,
                    color: AppColors.secondary,
                  ),
                  title: Text(
                    isBookmarked ? 'Remove Bookmark' : 'Bookmark Message',
                    style: const TextStyle(color: AppColors.textPrimaryDark),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final item = BookmarkedMessage(
                      messageId: message.id,
                      conversationId: conversationId ?? message.conversationId,
                      senderUsername:
                          otherUsername ?? (isMine ? 'You' : 'Anon'),
                      content: message.displayText,
                      isImage: message.isImage,
                      createdAt: message.createdAt,
                      bookmarkedAt: DateTime.now(),
                    );
                    final nowBookmarked = await ref
                        .read(bookmarksProvider.notifier)
                        .toggleBookmark(item);
                    if (context.mounted) {
                      context.showSnackBar(
                        nowBookmarked
                            ? 'Message bookmarked!'
                            : 'Bookmark removed.',
                      );
                    }
                  },
                ),
              ],
              if (!isMine)
                ListTile(
                  leading: const Icon(
                    Icons.flag_outlined,
                    color: AppColors.error,
                  ),
                  title: const Text(
                    'Report Message',
                    style: TextStyle(color: AppColors.error),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showReportDialog(context, ref);
                  },
                ),
              if (isMine && onDelete != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.error,
                  ),
                  title: const Text(
                    'Delete Message',
                    style: TextStyle(color: AppColors.error),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onDelete?.call();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context, WidgetRef ref) {
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
        title: const Text('Report Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a reason for reporting this message:',
              style: TextStyle(fontSize: 13, color: AppColors.textMutedDark),
            ),
            const SizedBox(height: 12),
            ...reasons.map(
              (r) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(r, style: const TextStyle(fontSize: 14)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await ref
                      .read(safetyRepositoryProvider)
                      .submitReport(
                        currentUserId: message.senderId,
                        reportedUserId: message.senderId,
                        conversationId:
                            conversationId ?? message.conversationId,
                        reason: r,
                        details: message.displayText,
                      );
                  if (context.mounted) {
                    context.showSnackBar(
                      'Thank you. The report has been received.',
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
}
