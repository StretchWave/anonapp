import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_control_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../messages/presentation/providers/notification_provider.dart';

/// Reorganized Settings Screen — Central hub for privacy, appearance,
/// notifications, security, and support subpages.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section: Privacy & Security
          _buildSectionHeader('Privacy & Controls'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _SettingsNavTile(
                  icon: Icons.shield_outlined,
                  title: 'Privacy & Safety',
                  subtitle: 'Who can message you, online status & receipts',
                  onTap: () => context.push('/settings/privacy'),
                ),
                const Divider(
                  height: 1,
                  indent: 56,
                  color: AppColors.surfaceBorder,
                ),
                _SettingsNavTile(
                  icon: Icons.block_rounded,
                  title: 'Blocked Users',
                  subtitle: 'Manage blocked anons and restrictions',
                  onTap: () => context.push('/settings/blocked'),
                ),
                const Divider(
                  height: 1,
                  indent: 56,
                  color: AppColors.surfaceBorder,
                ),
                _SettingsNavTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Security',
                  subtitle: 'Password, remember login & E2EE',
                  onTap: () => context.push('/settings/security'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section: Appearance & Interface
          _buildSectionHeader('Preferences'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _SettingsNavTile(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: 'Accent colors, bubble styles & dark theme',
                  onTap: () => context.push('/settings/appearance'),
                ),
                if (!kIsWeb) ...[
                  const Divider(
                    height: 1,
                    indent: 56,
                    color: AppColors.surfaceBorder,
                  ),
                  const _NotificationsInlineSection(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section: Support
          _buildSectionHeader('Support'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _SettingsNavTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & FAQ',
                  subtitle: 'Guides, privacy model & problem reports',
                  onTap: () => context.push('/settings/help'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // About Section
          const _AboutSection(),
          const SizedBox(height: 20),

          // Sign Out Action
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderColor: AppColors.error.withValues(alpha: 0.35),
            backgroundColor: AppColors.error.withValues(alpha: 0.08),
            onTap: () => _confirmSignOut(context, ref),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.2),
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

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariantDark,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primaryLight, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textMutedDark),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMutedDark,
        size: 20,
      ),
    );
  }
}

/// Inline mobile notifications configuration
class _NotificationsInlineSection extends ConsumerWidget {
  const _NotificationsInlineSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final enabled = settings.enabled;
    final discreet = settings.discreet;
    final statusAsync = ref.watch(pushNotificationStatusProvider);
    final status = statusAsync.valueOrNull;

    final isOsPermissionDenied =
        !kIsWeb && enabled && status != null && !status.osPermissionGranted;

    return Column(
      children: [
        SwitchListTile(
          value: enabled,
          onChanged: (val) {
            ref.read(notificationSettingsProvider.notifier).setEnabled(val);
          },
          activeThumbColor: AppColors.primaryLight,
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: AppColors.primaryLight,
              size: 20,
            ),
          ),
          title: const Text(
            'Message Notifications',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryDark,
            ),
          ),
          subtitle: const Text(
            'Receive alerts for new incoming encrypted chats',
            style: TextStyle(fontSize: 12, color: AppColors.textMutedDark),
          ),
        ),
        if (isOsPermissionDenied) ...[
          const Divider(height: 1, indent: 56, color: AppColors.surfaceBorder),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x1FFF9800),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66FF9800)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orangeAccent,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'OS Notifications Disabled',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Notifications are blocked in Android system settings. AnonApp cannot ring or vibrate until permitted.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        AppControlService.openNotificationSettings(),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Open Notification Settings'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (enabled) ...[
          const Divider(height: 1, indent: 56, color: AppColors.surfaceBorder),
          SwitchListTile(
            value: discreet,
            onChanged: (val) {
              ref.read(notificationSettingsProvider.notifier).setDiscreet(val);
            },
            activeThumbColor: AppColors.secondary,
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariantDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.visibility_off_outlined,
                color: AppColors.secondary,
                size: 20,
              ),
            ),
            title: const Text(
              'Discreet Lock Screen Mode',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryDark,
              ),
            ),
            subtitle: const Text(
              'Hides sender username and message snippet on lock screens',
              style: TextStyle(fontSize: 12, color: AppColors.textMutedDark),
            ),
          ),
          if (!kIsWeb && status != null) ...[
            const Divider(
              height: 1,
              indent: 56,
              color: AppColors.surfaceBorder,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_done_outlined,
                    size: 16,
                    color: AppColors.textMutedDark,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Push: FCM v1 (${status.maskedToken ?? 'active'})',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status.isSynced
                          ? Colors.greenAccent
                          : Colors.amberAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// About section
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
