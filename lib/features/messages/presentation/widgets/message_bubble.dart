import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../domain/models/message.dart';
import 'view_once_dialog.dart';
import 'voice_player.dart';

/// Bubble displaying an individual chat message with timestamps, status ticks,
/// and rich media (images, view-once photos, voice notes).
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onDelete,
    this.onViewOnceOpened,
  });

  final Message message;
  final bool isMine;
  final VoidCallback? onDelete;
  final VoidCallback? onViewOnceOpened;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Padding(
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
                  ? () => _showContextMenu(context)
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
      return VoicePlayer(
        base64Audio: message.mediaData ?? '',
        isMine: isMine,
        totalDurationMs: message.mediaMeta?['duration_ms'] as int?,
      );
    }

    // View-Once Photo
    if (message.isViewOnce) {
      return _buildViewOnceCard(context, theme);
    }

    // Normal Image
    if (message.isImage) {
      return _buildImageCard(context, theme);
    }

    // Standard text message
    return Text(
      message.displayText,
      style: TextStyle(
        fontSize: 15,
        color: isMine ? Colors.white : AppColors.textPrimaryDark,
        height: 1.35,
      ),
    );
  }

  Widget _buildViewOnceCard(BuildContext context, ThemeData theme) {
    final opened = message.isViewOnceOpened;

    return InkWell(
      onTap: () {
        if (opened) {
          context.showSnackBar('This view-once photo has already expired.');
          return;
        }
        if (isMine) {
          context.showSnackBar('You sent a view-once photo.');
          return;
        }
        ViewOnceDialog.show(
          context,
          message: message,
          onClosed: () => onViewOnceOpened?.call(),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withAlpha(25) : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: opened
                ? AppColors.surfaceBorder
                : (isMine
                      ? Colors.white38
                      : AppColors.secondary.withAlpha(120)),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: opened
                    ? Colors.white.withAlpha(15)
                    : (isMine
                          ? Colors.white24
                          : AppColors.secondary.withAlpha(35)),
              ),
              child: Icon(
                opened ? Icons.done_all_rounded : Icons.looks_one_rounded,
                size: 20,
                color: opened
                    ? (isMine ? Colors.white60 : AppColors.textMutedDark)
                    : (isMine ? Colors.white : AppColors.secondary),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  opened ? 'Photo (Opened)' : 'Photo (View Once)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: opened
                        ? (isMine ? Colors.white60 : AppColors.textMutedDark)
                        : (isMine ? Colors.white : AppColors.textPrimaryDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  opened
                      ? 'Expired'
                      : (isMine
                            ? 'Disappears after recipient views'
                            : 'Tap to view 1-time photo'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine
                        ? Colors.white70
                        : AppColors.textSecondaryDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageCard(BuildContext context, ThemeData theme) {
    Uint8List? bytes;
    if (message.mediaData != null) {
      try {
        bytes = base64Decode(message.mediaData!);
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bytes != null)
          GestureDetector(
            onTap: () => _showFullScreenImage(context, bytes!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 220,
              ),
            ),
          )
        else
          Container(
            height: 120,
            alignment: Alignment.center,
            child: Icon(
              Icons.image_not_supported_outlined,
              color: isMine ? Colors.white60 : AppColors.textMutedDark,
            ),
          ),
        if (message.content != null && message.content!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8, right: 8),
            child: Text(
              message.content!,
              style: TextStyle(
                fontSize: 14,
                color: isMine ? Colors.white : AppColors.textPrimaryDark,
              ),
            ),
          ),
      ],
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

  void _showContextMenu(BuildContext context) {
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
              if (message.content != null && message.content!.isNotEmpty)
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
}
