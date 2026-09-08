import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A subtle, looping 3-dot anonymous typing bubble.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, this.username});

  final String? username;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariantDark,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: AppColors.surfaceBorder, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final delay = index * 0.2;
                    final progress = (_controller.value - delay) % 1.0;
                    final bounce = (progress < 0.5)
                        ? (progress * 2)
                        : (1.0 - (progress - 0.5) * 2);
                    final scale = 0.6 + (bounce * 0.5);
                    final opacity = 0.4 + (bounce * 0.6);

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: 6.5,
                      height: 6.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryLight.withValues(
                          alpha: opacity,
                        ),
                      ),
                      transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                    );
                  },
                );
              }),
            ),
          ),
          if (widget.username != null) ...[
            const SizedBox(width: 8),
            Text(
              '@${widget.username} is typing...',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMutedDark,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
