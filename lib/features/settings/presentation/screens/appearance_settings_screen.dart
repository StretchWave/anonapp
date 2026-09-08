import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_card.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  int _selectedAccentIndex = 0;
  int _selectedBubbleIndex = 0;

  static const List<Map<String, dynamic>> _accents = [
    {
      'name': 'Neon Indigo',
      'color': Color(0xFF7C6EE6),
      'glow': Color(0xFF968AF0),
    },
    {
      'name': 'Cyber Teal',
      'color': Color(0xFF00D9A6),
      'glow': Color(0xFF55EFC4),
    },
    {
      'name': 'Sunset Violet',
      'color': Color(0xFFE056FD),
      'glow': Color(0xFFBE2EDD),
    },
    {
      'name': 'Crimson Flare',
      'color': Color(0xFFFF7675),
      'glow': Color(0xFFD63031),
    },
  ];

  static const List<String> _bubbleStyles = [
    'Modern Rounded (18px)',
    'Compact Sleek (12px)',
    'Curved Pill (24px)',
  ];

  @override
  Widget build(BuildContext context) {
    final activeAccent = _accents[_selectedAccentIndex];
    final activeColor = activeAccent['color'] as Color;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Appearance',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Live Chat Appearance Preview Card
          AppCard(
            useGradient: true,
            hasGlow: true,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.remove_red_eye_outlined,
                      size: 16,
                      color: AppColors.primaryLight,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Live Preview',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Incoming bubble sample
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariantDark,
                      borderRadius: BorderRadius.circular(
                        _selectedBubbleIndex == 0
                            ? 18
                            : (_selectedBubbleIndex == 1 ? 12 : 24),
                      ),
                      border: Border.all(
                        color: AppColors.surfaceBorder,
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'Hey anon, ready to chat?',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Outgoing bubble sample
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(
                        _selectedBubbleIndex == 0
                            ? 18
                            : (_selectedBubbleIndex == 1 ? 12 : 24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Always. End-to-end encrypted!',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Accent Color Selector
          _buildSectionHeader('Accent Color'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_accents.length, (idx) {
              final acc = _accents[idx];
              final isSelected = _selectedAccentIndex == idx;
              final col = acc['color'] as Color;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedAccentIndex = idx);
                  context.showSnackBar('Accent updated to ${acc['name']}');
                },
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: col,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: col.withValues(alpha: 0.5),
                            blurRadius: isSelected ? 12 : 4,
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 24,
                            )
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      acc['name'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected
                            ? AppColors.textPrimaryDark
                            : AppColors.textMutedDark,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // Bubble Style Selector
          _buildSectionHeader('Chat Bubble Style'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: List.generate(_bubbleStyles.length, (idx) {
                final isSelected = _selectedBubbleIndex == idx;
                return ListTile(
                  onTap: () {
                    setState(() => _selectedBubbleIndex = idx);
                    context.showSnackBar('Bubble style updated.');
                  },
                  leading: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? activeColor
                            : AppColors.textMutedDark,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isSelected
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: activeColor,
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    _bubbleStyles[idx],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 24),

          // App Theme Mode
          _buildSectionHeader('Theme Mode'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.dark_mode_rounded,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Dark-First Canvas',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryLight,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
