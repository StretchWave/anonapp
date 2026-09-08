import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) const SizedBox(width: 4),
          Flexible(
            child: GestureDetector(
              onLongPress: isMine && !message.isDeleted && onDelete != null
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
                  color: isMine
                      ? (message.status == MessageStatus.failed
                            ? AppColors.error.withAlpha(200)
                            : AppColors.primary)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMine ? 18 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildContent(context, theme),
                    const SizedBox(height: 4),
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
                                  ? Colors.white.withAlpha(180)
                                  : theme.colorScheme.onSurface.withAlpha(130),
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
                ? Colors.white.withAlpha(180)
                : theme.colorScheme.onSurface.withAlpha(150),
          ),
          const SizedBox(width: 6),
          Text(
            message.displayText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: isMine
                  ? Colors.white.withAlpha(180)
                  : theme.colorScheme.onSurface.withAlpha(150),
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
      style: theme.textTheme.bodyMedium?.copyWith(
        color: isMine ? Colors.white : theme.colorScheme.onSurface,
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withAlpha(30)
              : AppColors.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: opened
                ? Colors.transparent
                : (isMine ? Colors.white54 : AppColors.accent),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: opened
                    ? Colors.grey.withAlpha(50)
                    : (isMine
                          ? Colors.white24
                          : AppColors.accent.withAlpha(40)),
              ),
              child: Icon(
                opened ? Icons.done_all_rounded : Icons.looks_one_rounded,
                size: 20,
                color: opened
                    ? (isMine ? Colors.white60 : Colors.grey)
                    : (isMine ? Colors.white : AppColors.accent),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  opened ? 'Photo (Opened)' : 'Photo (View once)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: opened
                        ? (isMine ? Colors.white60 : Colors.grey)
                        : (isMine ? Colors.white : theme.colorScheme.onSurface),
                    fontStyle: opened ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                Text(
                  opened
                      ? 'Expired'
                      : (isMine
                            ? 'Disappears after recipient views'
                            : 'Tap to view once'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine ? Colors.white70 : Colors.black54,
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
              color: isMine ? Colors.white60 : Colors.grey,
            ),
          ),
        if (message.content != null && message.content!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8, right: 8),
            child: Text(
              message.content!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isMine ? Colors.white : theme.colorScheme.onSurface,
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
          color: AppColors.accent,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    );
  }
}
