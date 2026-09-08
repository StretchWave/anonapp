import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/file_cleanup.dart';
import 'image_preview_dialog.dart';

/// Text and rich media input bar supporting Enter-to-send, voice recording,
/// normal images, and view-once images.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onSendImage,
    this.onSendVoice,
    this.enabled = true,
  });

  final ValueChanged<String> onSend;
  final OnSendImageCallback? onSendImage;
  final void Function(String base64Audio, int durationMs)? onSendVoice;
  final bool enabled;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();

  bool _canSend = false;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  DateTime? _recordStartTime;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final canSend = _controller.text.trim().isNotEmpty;
      if (canSend != _canSend) {
        setState(() => _canSend = canSend);
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
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

  Future<void> _pickAndPreviewImage() async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (xFile == null || !mounted) return;

      final bytes = await xFile.readAsBytes();
      if (!mounted) return;

      await ImagePreviewDialog.show(
        context,
        imageBytes: bytes,
        onSend: (base64Img, caption, isViewOnce) {
          widget.onSendImage?.call(base64Img, caption, isViewOnce);
        },
      );
    } catch (e) {
      debugPrint('[ChatInputBar] Error picking image: $e');
      if (mounted) {
        context.showSnackBar(
          'Could not open image picker: $e\n'
          'Note: If packages were newly installed, please stop and restart `flutter run`.',
          isError: true,
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          context.showSnackBar(
            'Microphone permission required. Please allow access.',
            isError: true,
          );
        }
        return;
      }

      // Determine the best supported audio encoder for the platform
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

      // Generate temp path for native platforms; web uses browser in-memory blobs
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
        context.showSnackBar(
          'Could not start recording: $e\n'
          'Note: If packages were newly installed, please stop and restart `flutter run`.',
          isError: true,
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordTimer?.cancel();
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
        // Immediately clean up temporary unencrypted audio file from disk
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
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
            width: 0.5,
          ),
        ),
      ),
      child: _isRecording ? _buildRecordingBar(theme) : _buildInputBar(theme),
    );
  }

  Widget _buildRecordingBar(ThemeData theme) {
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
        const SizedBox(width: 8),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatRecordTime(_recordSeconds),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            fontSize: 16,
          ),
        ),
        const Spacer(),
        const Text(
          'Recording anonymous audio...',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const Spacer(),
        FloatingActionButton.small(
          onPressed: _stopAndSendRecording,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.arrow_upward_rounded),
        ),
      ],
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Image attachment button
        IconButton(
          icon: const Icon(Icons.add_photo_alternate_outlined),
          tooltip: 'Send photo',
          color: theme.colorScheme.onSurface.withAlpha(180),
          onPressed: widget.enabled ? _pickAndPreviewImage : null,
        ),

        // Text input field with Enter-to-send support
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
              borderRadius: BorderRadius.circular(24),
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
                decoration: const InputDecoration(
                  hintText: 'Type an anonymous message...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Send button or Microphone button
        if (_canSend)
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_upward_rounded),
              color: Colors.white,
              iconSize: 20,
              tooltip: 'Send message (Enter)',
              onPressed: widget.enabled ? _handleSend : null,
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.mic_none_rounded),
            color: AppColors.primary,
            iconSize: 26,
            tooltip: 'Record voice note',
            onPressed: widget.enabled ? _startRecording : null,
          ),
      ],
    );
  }
}
