import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../providers/session_settings_provider.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isUpdating = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final pass = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (pass.length < 6) {
      context.showSnackBar(
        'Password must be at least 6 characters long.',
        isError: true,
      );
      return;
    }
    if (pass != confirm) {
      context.showSnackBar('Passwords do not match.', isError: true);
      return;
    }

    setState(() => _isUpdating = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.auth.updateUser(UserAttributes(password: pass));
      if (mounted) {
        context.showSnackBar('Password updated successfully!');
        _passwordController.clear();
        _confirmController.clear();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to update password: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Security',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // E2EE Architecture Badge Card
          AppCard(
            useGradient: true,
            hasGlow: true,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.secondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AES-256-GCM End-to-End Encryption',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'All text chats are encrypted locally on your device before transmission. Only conversation participants hold the decryption key.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMutedDark,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Change Password Section
          _buildSectionHeader('Change Password'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(
                    color: AppColors.textPrimaryDark,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: const TextStyle(color: AppColors.textMutedDark),
                    prefixIcon: const Icon(
                      Icons.lock_reset_rounded,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceVariantDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  style: const TextStyle(
                    color: AppColors.textPrimaryDark,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    labelStyle: const TextStyle(color: AppColors.textMutedDark),
                    prefixIcon: const Icon(
                      Icons.lock_clock_rounded,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceVariantDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(
                  text: 'Update Password',
                  icon: Icons.check_rounded,
                  isLoading: _isUpdating,
                  variant: AppButtonVariant.primary,
                  onPressed: _updatePassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Session & Login Persistence Section
          _buildSectionHeader('Session & Login Persistence'),
          const SizedBox(height: 8),
          Consumer(
            builder: (context, ref, _) {
              final rememberAsync = ref.watch(rememberLoginProvider);
              final remember = rememberAsync.valueOrNull ?? true;

              return AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: remember
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            remember
                                ? Icons.lock_clock_rounded
                                : Icons.history_toggle_off_rounded,
                            color: remember
                                ? AppColors.primaryLight
                                : Colors.amberAccent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Remember Login Information',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimaryDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                remember
                                    ? 'Keep session active across browser restarts and tab closures.'
                                    : 'Forget login automatically as soon as this tab or website is closed.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMutedDark,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: remember,
                          activeThumbColor: AppColors.primaryLight,
                          activeTrackColor: AppColors.primary.withValues(
                            alpha: 0.5,
                          ),
                          inactiveThumbColor: Colors.amberAccent,
                          inactiveTrackColor: Colors.amber.withValues(
                            alpha: 0.3,
                          ),
                          onChanged: (val) async {
                            await ref
                                .read(rememberLoginProvider.notifier)
                                .setRememberLogin(val);
                            if (context.mounted) {
                              context.showSnackBar(
                                val
                                    ? 'Login will be remembered on this device.'
                                    : 'Login will be forgotten when you close the tab or exit the website.',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: remember
                            ? AppColors.surfaceVariantDark.withValues(
                                alpha: 0.5,
                              )
                            : Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: remember
                              ? AppColors.surfaceBorder
                              : Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            remember
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            size: 16,
                            color: remember
                                ? AppColors.secondary
                                : Colors.amberAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              remember
                                  ? 'Persistent Mode: Login token is stored on this device.'
                                  : 'Ephemeral Mode: Zero credentials stored permanently. Tab close wipes session.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: remember
                                    ? AppColors.textSecondaryDark
                                    : Colors.amberAccent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Active Session Card
          _buildSectionHeader('Active Session'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.smartphone_rounded,
                    color: AppColors.primaryLight,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This Device',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Active now · Pseudonymous Token Session',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
