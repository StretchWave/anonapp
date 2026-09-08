import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Callback when user confirms sending an image.
typedef OnSendImageCallback =
    void Function(String base64Image, String? caption, bool isViewOnce);

/// Modal dialog showing picked image preview with caption and View-Once toggle.
class ImagePreviewDialog extends StatefulWidget {
  const ImagePreviewDialog({
    super.key,
    required this.imageBytes,
    required this.onSend,
    this.isViewOnceDefault = false,
  });

  final Uint8List imageBytes;
  final OnSendImageCallback onSend;
  final bool isViewOnceDefault;

  static Future<void> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required OnSendImageCallback onSend,
    bool isViewOnceDefault = false,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ImagePreviewDialog(
        imageBytes: imageBytes,
        onSend: onSend,
        isViewOnceDefault: isViewOnceDefault,
      ),
    );
  }

  @override
  State<ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<ImagePreviewDialog> {
  final _captionController = TextEditingController();
  late bool _isViewOnce;

  @override
  void initState() {
    super.initState();
    _isViewOnce = widget.isViewOnceDefault;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final base64String = base64Encode(widget.imageBytes);
    final caption = _captionController.text.trim();
    widget.onSend(
      base64String,
      caption.isNotEmpty ? caption : null,
      _isViewOnce,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Text(
                  _isViewOnce ? 'View-Once Photo' : 'Send Photo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // View Once Toggle button
                FilterChip(
                  avatar: Icon(
                    Icons.looks_one_rounded,
                    size: 18,
                    color: _isViewOnce ? Colors.white : AppColors.accent,
                  ),
                  label: const Text('View Once'),
                  selected: _isViewOnce,
                  selectedColor: AppColors.accent,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _isViewOnce
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  onSelected: (selected) {
                    setState(() => _isViewOnce = selected);
                  },
                ),
              ],
            ),
          ),

          // Image preview area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: Colors.black.withAlpha(20),
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
          ),

          // Caption & Send controls
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: bottomInset + 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _captionController,
                    decoration: InputDecoration(
                      hintText: 'Add an anonymous caption...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  onPressed: _handleSend,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
