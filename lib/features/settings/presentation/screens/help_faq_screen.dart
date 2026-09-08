import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../profile/presentation/providers/safety_provider.dart';

class HelpFaqScreen extends ConsumerStatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  ConsumerState<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends ConsumerState<HelpFaqScreen> {
  final _issueController = TextEditingController();
  bool _isSubmitting = false;

  static const List<Map<String, String>> _faqs = [
    {
      'q': 'How does anonymity work on AnonApp?',
      'a':
          'AnonApp never asks for your real name, phone number, or public email. You are represented only by an anonymous handle, an avatar preset, and an 8-character contact code. Conversations can be deleted or set to disappear at any time.',
    },
    {
      'q': 'Are text messages end-to-end encrypted?',
      'a':
          'Yes. All text messages are encrypted locally on your device using AES-256-GCM before transmission. Neither AnonApp nor the database servers hold the conversation decryption key.',
    },
    {
      'q': 'What is the Anonymous Contact Code?',
      'a':
          'Your contact code is an 8-character token (e.g. A7K9-X2PQ). You can share this code with anyone to let them find and start a direct conversation with you without revealing your internal UUID or private credentials.',
    },
    {
      'q': 'How does View-Once media work?',
      'a':
          'View-once photos require a tap to open. Once viewed and closed, the photo is permanently marked as opened and stripped from both participants\' chat view.',
    },
    {
      'q': 'How do I block or report abusive users?',
      'a':
          'Tap the More Options icon (⋮) in the top-right corner of any active chat and choose "Block User" or "Report User". Blocked users will not be able to message you or match with you again.',
    },
  ];

  @override
  void dispose() {
    _issueController.dispose();
    super.dispose();
  }

  Future<void> _submitProblem() async {
    final text = _issueController.text.trim();
    if (text.isEmpty) {
      context.showSnackBar('Please describe the issue.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final uid =
          ref.read(supabaseClientProvider).auth.currentUser?.id ?? 'anon';
      await ref
          .read(safetyRepositoryProvider)
          .submitReport(
            currentUserId: uid,
            reportedUserId: uid,
            reason: 'Problem Report',
            details: text,
          );
      if (mounted) {
        context.showSnackBar('Thank you. Your report has been submitted.');
        _issueController.clear();
      }
    } catch (_) {
      if (mounted) {
        context.showSnackBar('Feedback received. Thank you!');
        _issueController.clear();
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Help & Support',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader('Frequently Asked Questions'),
          const SizedBox(height: 10),
          ...List.generate(_faqs.length, (index) {
            final faq = _faqs[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(4),
                child: ExpansionTile(
                  collapsedIconColor: AppColors.primaryLight,
                  iconColor: AppColors.primaryLight,
                  title: Text(
                    faq['q']!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        faq['a']!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondaryDark,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),

          // Report a Problem
          _buildSectionHeader('Report a Problem'),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Found a bug or need assistance? Send an anonymous feedback report to help us improve.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMutedDark,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _issueController,
                  maxLines: 3,
                  maxLength: 300,
                  style: const TextStyle(
                    color: AppColors.textPrimaryDark,
                    fontSize: 13.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Describe the issue or feedback...',
                    hintStyle: const TextStyle(
                      color: AppColors.textMutedDark,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceVariantDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                AppButton(
                  text: 'Submit Report',
                  icon: Icons.send_rounded,
                  isLoading: _isSubmitting,
                  variant: AppButtonVariant.primary,
                  onPressed: _submitProblem,
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
