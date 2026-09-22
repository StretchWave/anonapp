import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/file_cleanup.dart';
import '../providers/message_provider.dart';
import 'attachment_sheet.dart';
import 'image_preview_dialog.dart';

/// Modern chat input bar supporting multiline text (Enter to send),
/// rich attachment sheet (gallery, camera, view-once), voice recording,
/// swipe-to-reply preview banner, and real-time typing indicators.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onSendImage,
    this.onSendVoice,
    this.onSendDocument,
    this.enabled = true,
    this.replyMessage,
    this.onCancelReply,
    this.onTyping,
  });

  final ValueChanged<String> onSend;
  final OnSendImageCallback? onSendImage;
  final void Function(String base64Audio, int durationMs)? onSendVoice;
  final void Function(
    String base64Doc,
    String fileName,
    int fileSize,
    String? extension,
  )?
  onSendDocument;
  final bool enabled;
  final ReplyMessageInfo? replyMessage;
  final VoidCallback? onCancelReply;
  final VoidCallback? onTyping;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  DateTime? _recordStartTime;

  bool _canSend = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _controller.addListener(() {
      final canSend = _controller.text.trim().isNotEmpty;
      if (canSend != _canSend) {
        setState(() => _canSend = canSend);
      }
      if (canSend) {
        widget.onTyping?.call();
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pulseController.dispose();
    _audioRecorder.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _handleSend();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openAttachmentMenu() {
    AttachmentSheet.show(
      context,
      onSelect: (type) {
        switch (type) {
          case AttachmentType.gallery:
            _pickImage(ImageSource.gallery, defaultViewOnce: false);
            break;
          case AttachmentType.camera:
            _pickImage(ImageSource.camera, defaultViewOnce: false);
            break;
          case AttachmentType.document:
            _pickDocument();
            break;
          case AttachmentType.voice:
            _startRecording();
            break;
        }
      },
    );
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final ioFile = File(file.path!);
        if (await ioFile.exists()) {
          bytes = await ioFile.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          context.showSnackBar('Unable to read selected file.', isError: true);
        }
        return;
      }

      // 15 MB limit for document transfer
      if (bytes.length > 15 * 1024 * 1024) {
        if (mounted) {
          context.showSnackBar('File size exceeds 15 MB limit.', isError: true);
        }
        return;
      }

      final base64Doc = base64Encode(bytes);
      widget.onSendDocument?.call(
        base64Doc,
        file.name,
        file.size,
        file.extension,
      );
    } catch (e) {
      debugPrint('[ChatInputBar] Error picking document: $e');
      if (mounted) {
        context.showSnackBar('Could not pick document: $e', isError: true);
      }
    }
  }

  Future<void> _pickImage(
    ImageSource source, {
    required bool defaultViewOnce,
  }) async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (xFile == null || !mounted) return;

      final bytes = await xFile.readAsBytes();
      if (!mounted) return;

      await ImagePreviewDialog.show(
        context,
        imageBytes: bytes,
        isViewOnceDefault: defaultViewOnce,
        onSend: (base64Img, caption, isViewOnce) {
          widget.onSendImage?.call(base64Img, caption, isViewOnce);
        },
      );
    } catch (e) {
      debugPrint('[ChatInputBar] Error picking image: $e');
      if (mounted) {
        context.showSnackBar('Could not access image: $e', isError: true);
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          context.showSnackBar(
            'Microphone permission required for voice notes.',
            isError: true,
          );
        }
        return;
      }

      AudioEncoder encoder = AudioEncoder.aacLc;
      if (kIsWeb) {
        final isOpus = await _audioRecorder.isEncoderSupported(
          AudioEncoder.opus,
        );
        encoder = isOpus ? AudioEncoder.opus : AudioEncoder.aacLc;
      } else {
        final isAac = await _audioRecorder.isEncoderSupported(
          AudioEncoder.aacLc,
        );
        encoder = isAac ? AudioEncoder.aacLc : AudioEncoder.opus;
      }

      String targetPath = '';
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        final ext = encoder == AudioEncoder.opus ? 'webm' : 'm4a';
        targetPath =
            '${tempDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.$ext';
      }

      final config = RecordConfig(encoder: encoder);
      await _audioRecorder.start(config, path: targetPath);
      _recordStartTime = DateTime.now();

      unawaited(_pulseController.repeat(reverse: true));

      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
        });
      }

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordSeconds++);
        }
      });
    } catch (e) {
      debugPrint('[ChatInputBar] Error starting recording: $e');
      if (mounted) {
        context.showSnackBar('Could not start recording: $e', isError: true);
      }
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordTimer?.cancel();
      _pulseController.stop();
      final path = await _audioRecorder.stop();
      await deleteTempFile(path);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
      });
    }
  }

  Future<void> _stopAndSendRecording() async {
    try {
      _recordTimer?.cancel();
      _pulseController.stop();
      final path = await _audioRecorder.stop();
      final durationMs = _recordStartTime != null
          ? DateTime.now().difference(_recordStartTime!).inMilliseconds
          : _recordSeconds * 1000;

      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordSeconds = 0;
        });
      }

      if (path != null && path.isNotEmpty) {
        final xFile = XFile(path);
        final bytes = await xFile.readAsBytes();
        await deleteTempFile(path);
        final base64Audio = base64Encode(bytes);
        widget.onSendVoice?.call(base64Audio, durationMs);
      } else {
        if (mounted) {
          context.showSnackBar(
            'Recording produced no audio data.',
            isError: true,
          );
        }
      }
    } catch (e) {
      debugPrint('[ChatInputBar] Error stopping recording: $e');
      if (mounted) {
        setState(() => _isRecording = false);
        context.showSnackBar('Failed to process voice note: $e', isError: true);
      }
    }
  }

  String _formatRecordTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: 12,
        top: 8,
        bottom: bottomInset > 0 ? bottomInset + 4 : 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder, width: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyMessage != null) _buildReplyPreview(),
          _isRecording ? _buildRecordingBar() : _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    final reply = widget.replyMessage!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.reply_rounded,
            size: 18,
            color: AppColors.primaryLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply.senderName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryDark,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textMutedDark,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            splashRadius: 16,
            onPressed: widget.onCancelReply,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: AppColors.error,
          ),
          tooltip: 'Discard',
          onPressed: _cancelRecording,
        ),
        const SizedBox(width: 6),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) => Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.error.withValues(
                alpha: 0.4 + (_pulseController.value * 0.6),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.error.withValues(alpha: 0.5),
                  blurRadius: 6 * _pulseController.value,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatRecordTime(_recordSeconds),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            fontSize: 15,
            color: AppColors.textPrimaryDark,
          ),
        ),
        const Spacer(),
        const Text(
          'Recording anonymous audio...',
          style: TextStyle(fontSize: 12, color: AppColors.textMutedDark),
        ),
        const Spacer(),
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: AppColors.primaryGlow,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            color: Colors.white,
            onPressed: _stopAndSendRecording,
          ),
        ),
      ],
    );
  }

  Widget _buildInputBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Attachment Plus Button
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded),
          tooltip: 'Share media',
          color: AppColors.primaryLight,
          onPressed: widget.enabled ? _openAttachmentMenu : null,
        ),

        // Text input field with Enter-to-send
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.surfaceBorder, width: 1),
            ),
            child: Focus(
              onKeyEvent: _handleKeyEvent,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimaryDark,
                ),
                decoration: const InputDecoration(
                  hintText: 'Type an anonymous message...',
                  hintStyle: TextStyle(
                    color: AppColors.textMutedDark,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Morphing Action button (Mic <-> Send Arrow)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: _canSend
              ? Container(
                  key: const ValueKey('send_btn'),
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppColors.primaryGlow,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    color: Colors.white,
                    iconSize: 20,
                    tooltip: 'Send message (Enter)',
                    onPressed: widget.enabled ? _handleSend : null,
                  ),
                )
              : Container(
                  key: const ValueKey('mic_btn'),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariantDark,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.surfaceBorder,
                      width: 1,
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.mic_rounded),
                    color: AppColors.primaryLight,
                    iconSize: 20,
                    tooltip: 'Record voice note',
                    onPressed: widget.enabled ? _startRecording : null,
                  ),
                ),
        ),
      ],
    );
  }
}
