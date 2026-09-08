import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../providers/auth_provider.dart';

/// Onboarding / Welcome screen showcasing the anonymous-first concept.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _isAnonLoading = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Auto-generates a secure pseudonym and logs in immediately with 1-click.
  Future<void> _handleContinueAnonymously() async {
    setState(() => _isAnonLoading = true);

    try {
      final rand = Random();
      const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
      final randomSuffix = List.generate(
        6,
        (index) => chars[rand.nextInt(chars.length)],
      ).join();
      final username = 'anon_$randomSuffix';
      final password = 'AnonPass!${rand.nextInt(900000) + 100000}#';

      await ref
          .read(authNotifierProvider.notifier)
          .signUp(username: username, password: password);

      final authState = ref.read(authNotifierProvider);
      if (authState.hasError) {
        final error = authState.error;
        if (mounted) {
          final message = error is AppException
              ? error.message
              : 'Could not create anonymous session. Please try again.';
          context.showSnackBar(message, isError: true);
        }
      }
      // Router handles navigation to /main upon authState update
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Anonymous sign-in failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isAnonLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Subtle ambient glow at top
          Positioned(
            top: -100,
            left: -50,
            right: -50,
            height: 380,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [
                    Color(0x387C6EE6),
                    Color(0x1000D9A6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 2),

                      // Logo and Brand Emblem
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: AppColors.primaryGlow,
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            size: 46,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // App Name & Tagline
                      Text(
                        'AnonApp',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'An elegant, private place to have a conversation.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondaryDark,
                          height: 1.4,
                        ),
                      ),

                      const Spacer(flex: 2),

                      // Value propositions
                      _buildFeatureTile(
                        icon: Icons.no_accounts_rounded,
                        title: 'Pure Pseudonymity',
                        subtitle:
                            'No phone numbers, emails, or real names required.',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'End-to-End Encrypted',
                        subtitle:
                            'Text messages encrypted with AES-256-GCM cipher.',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureTile(
                        icon: Icons.timer_outlined,
                        title: 'Ephemeral Conversations',
                        subtitle:
                            'Set disappearing messages or clear chat at any time.',
                      ),

                      const Spacer(flex: 3),

                      // Action Buttons
                      AppButton(
                        text: 'Get Started',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => context.push(AppRoutes.register),
                      ),
                      const SizedBox(height: 12),

                      AppButton(
                        text: 'Continue Anonymously',
                        icon: Icons.flash_on_rounded,
                        variant: AppButtonVariant.secondary,
                        isLoading: _isAnonLoading,
                        onPressed: _handleContinueAnonymously,
                      ),
                      const SizedBox(height: 14),

                      // Sign In Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondaryDark,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.push(AppRoutes.login),
                            child: const Text(
                              'Sign In',
                              style: TextStyle(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
