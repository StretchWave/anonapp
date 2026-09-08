import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

enum AttachmentType { gallery, camera, viewOnce, voice }

/// Sleek modal bottom sheet for choosing chat attachment types.
class AttachmentSheet extends StatelessWidget {
  const AttachmentSheet({super.key, required this.onSelect});

  final void Function(AttachmentType type) onSelect;

  static Future<void> show(
    BuildContext context, {
    required void Function(AttachmentType type) onSelect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AttachmentSheet(onSelect: onSelect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMutedDark.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Share Content',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select media to share anonymously in this chat',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryDark,
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionItem(
                  context,
                  type: AttachmentType.gallery,
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: const Color(0xFF6C63FF),
                ),
                _buildActionItem(
                  context,
                  type: AttachmentType.camera,
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  color: const Color(0xFF00D9A6),
                ),
                _buildActionItem(
                  context,
                  type: AttachmentType.viewOnce,
                  icon: Icons.looks_one_rounded,
                  label: 'View-Once',
                  color: const Color(0xFFFF9F43),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required AttachmentType type,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onSelect(type);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(60), width: 1.2),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
