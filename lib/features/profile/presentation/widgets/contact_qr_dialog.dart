import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';

/// Modal dialog displaying the anonymous contact code with a digital QR matrix.
class ContactQrDialog extends StatelessWidget {
  const ContactQrDialog({super.key, required this.contactCode});

  final String contactCode;

  String get _formattedCode {
    if (contactCode.length == 8) {
      return '${contactCode.substring(0, 4)} - ${contactCode.substring(4)}';
    }
    return contactCode;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AppCard(
        useGradient: true,
        hasGlow: true,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      color: AppColors.primaryLight,
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Contact Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.textMutedDark,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // High-tech QR Canvas Container
            Container(
              width: 190,
              height: 190,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _AnonymousMatrixPainter(seed: contactCode),
              ),
            ),
            const SizedBox(height: 20),

            // Formatted Monospace Code
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariantDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder, width: 1),
              ),
              child: Text(
                _formattedCode,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                  color: AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(height: 14),

            const Text(
              'Share this code with others to start an encrypted chat without exposing your email, phone number, or identity.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textMutedDark,
              ),
            ),
            const SizedBox(height: 22),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Copy Code',
                    icon: Icons.copy_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: contactCode));
                      context.showSnackBar('Contact code copied to clipboard!');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    text: 'Share',
                    icon: Icons.share_rounded,
                    variant: AppButtonVariant.primary,
                    onPressed: () {
                      final shareText =
                          'Connect with me anonymously on AnonApp using my contact code: $contactCode';
                      Clipboard.setData(ClipboardData(text: shareText));
                      context.showSnackBar(
                        'Share message copied to clipboard!',
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a deterministic geometric QR/matrix pattern seeded by the code.
class _AnonymousMatrixPainter extends CustomPainter {
  _AnonymousMatrixPainter({required this.seed});

  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0D1117)
      ..style = PaintingStyle.fill;

    const gridSize = 17;
    final cellSize = size.width / gridSize;
    final rand = Random(seed.hashCode);

    // Draw Corner Position Detection Squares
    void drawPositionSquare(double x, double y) {
      // Outer 5x5
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * cellSize, y * cellSize, 5 * cellSize, 5 * cellSize),
          const Radius.circular(3),
        ),
        paint,
      );
      // Inner white 3x3
      canvas.drawRect(
        Rect.fromLTWH(
          (x + 1) * cellSize,
          (y + 1) * cellSize,
          3 * cellSize,
          3 * cellSize,
        ),
        Paint()..color = Colors.white,
      );
      // Center 1x1 black
      canvas.drawRect(
        Rect.fromLTWH(
          (x + 2) * cellSize,
          (y + 2) * cellSize,
          cellSize,
          cellSize,
        ),
        paint,
      );
    }

    drawPositionSquare(0, 0);
    drawPositionSquare(gridSize - 5, 0);
    drawPositionSquare(0, gridSize - 5);

    // Fill pseudo-random matrix pattern
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        // Skip corner patterns
        if ((r < 6 && c < 6) ||
            (r < 6 && c >= gridSize - 6) ||
            (r >= gridSize - 6 && c < 6)) {
          continue;
        }

        if (rand.nextBool()) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                c * cellSize + 0.5,
                r * cellSize + 0.5,
                cellSize - 1,
                cellSize - 1,
              ),
              const Radius.circular(1.5),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnonymousMatrixPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
