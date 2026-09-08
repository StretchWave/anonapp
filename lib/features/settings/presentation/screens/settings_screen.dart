import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../messages/presentation/providers/notification_provider.dart';

/// Redesigned Identity and Settings screen with grouped cards,
/// contact code showcase, and security guarantees.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Identity & Settings',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading profile: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No active profile found'));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Profile Hero Header
              _ProfileHeroCard(profile: profile),
              const SizedBox(height: 14),

              // Anonymous Contact Code Card
              if (profile.contactCode != null) ...[
                _ContactCodeCard(code: profile.contactCode!),
                const SizedBox(height: 14),
              ],

              // Mobile Notifications (Android & iOS only)
              if (!kIsWeb) ...[
                const _NotificationsSection(),
                const SizedBox(height: 14),
              ],

              // Security & Privacy Guarantees
              const _SecuritySection(),
              const SizedBox(height: 14),

              // Appearance & About Section
              const _AboutSection(),
              const SizedBox(height: 20),

              // Destructive Action: Sign Out
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                borderColor: AppColors.error.withAlpha(40),
                backgroundColor: AppColors.error.withAlpha(12),
                onTap: () => _confirmSignOut(context, ref),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sign Out',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'End your current pseudonymous session',
                            style: TextStyle(
                              color: AppColors.textMutedDark,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMutedDark,
                      size: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.error, size: 22),
            SizedBox(width: 10),
            Text('Sign Out?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to end this session? You will need your username and password to log back in.',
          style: TextStyle(color: AppColors.textSecondaryDark, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
  }
}

/// Profile Hero header card with avatar and username.
class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({required this.profile});

  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    final username = profile.username as String;
    final userId = profile.id as String;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return AppCard(
      useGradient: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Avatar with gradient border
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradient,
              boxShadow: AppColors.primaryGlow,
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cardDark,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Text(
            '@$username',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: 6),

          // Anonymity Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.secondary.withAlpha(25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.secondary.withAlpha(60),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 13,
                  color: AppColors.secondary,
                ),
                SizedBox(width: 6),
                Text(
                  'Verified Anonymous',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Divider(color: AppColors.dividerDark),
          const SizedBox(height: 8),

          // User ID quick copy
          Row(
            children: [
              const Icon(
                Icons.fingerprint_rounded,
                size: 18,
                color: AppColors.textMutedDark,
              ),
              const SizedBox(width: 8),
              const Text(
                'User ID:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  userId,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppColors.textMutedDark,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy ID',
                color: AppColors.primaryLight,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: userId));
                  context.showSnackBar('User ID copied to clipboard');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stylized Contact Code Showcase Card.
class _ContactCodeCard extends StatelessWidget {
  const _ContactCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.primary.withAlpha(120),
      hasGlow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                color: AppColors.primaryLight,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Anonymous Contact Code',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Share this code so other anons can reach you without revealing your identity.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryDark,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withAlpha(60),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: AppColors.primaryLight,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                AppButton(
                  text: 'Copy',
                  icon: Icons.copy_rounded,
                  width: 86,
                  height: 38,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    context.showSnackBar('Contact code copied to clipboard!');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile Notifications settings card.
class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: AppColors.primaryLight,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Message Notifications',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Alerts for incoming anonymous messages',
              style: TextStyle(fontSize: 12, color: AppColors.textMutedDark),
            ),
            value: settings.enabled,
            onChanged: (val) => notifier.setEnabled(val),
          ),
          if (settings.enabled) ...[
            const Divider(color: AppColors.dividerDark),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Discreet Mode',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Hide sender handle and previews on lock screen',
                style: TextStyle(fontSize: 12, color: AppColors.textMutedDark),
              ),
              value: settings.discreet,
              onChanged: (val) => notifier.setDiscreet(val),
            ),
          ],
        ],
      ),
    );
  }
}

/// Privacy and security guarantees breakdown card.
class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.security_rounded,
                color: AppColors.secondary,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Security & Privacy Architecture',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildItem(
            icon: Icons.lock_outline_rounded,
            title: 'Selective AES-256-GCM',
            description: 'All text messages are encrypted on your device.',
          ),
          const SizedBox(height: 10),
          _buildItem(
            icon: Icons.no_accounts_outlined,
            title: 'Zero Personal Telemetry',
            description: 'No real names, phone numbers, or emails are exposed.',
          ),
          const SizedBox(height: 10),
          _buildItem(
            icon: Icons.remove_red_eye_outlined,
            title: 'Participant-Only RLS',
            description:
                'Database policies enforce access strictly to conversation members.',
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryDark,
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMutedDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// About and version info section.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimaryDark,
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Version',
                style: TextStyle(fontSize: 13, color: AppColors.textMutedDark),
              ),
              Text(
                '1.0.0+1 (Release)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Theme',
                style: TextStyle(fontSize: 13, color: AppColors.textMutedDark),
              ),
              Text(
                'Dark Modern',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
