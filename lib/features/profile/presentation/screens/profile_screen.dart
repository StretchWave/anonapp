import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/domain/models/user_profile.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/profile_repository.dart';
import '../providers/profile_provider.dart';
import '../widgets/contact_qr_dialog.dart';

/// Full Profile Experience — Personal control center for anonymous identity,
/// stats, interests, contact code, and quick access to settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentEnrichedProfileProvider);
    final statsAsync = ref.watch(profileStatsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading profile: $err',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile not available.'));
          }

          final stats =
              statsAsync.valueOrNull ?? {'chats': 0, 'bookmarks': 0, 'days': 1};
          final preset = AnonymousAvatars.getPreset(profile.avatar);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              // 1. Profile Hero Card
              _buildHeroCard(context, profile, preset),
              const SizedBox(height: 14),

              // 2. Profile Stats Row
              _buildStatsRow(stats),
              const SizedBox(height: 14),

              // 3. Interests Section
              _buildInterestsSection(context, profile),
              const SizedBox(height: 14),

              // 4. Anonymous Contact Code Card
              if (profile.contactCode != null) ...[
                _buildContactCodeCard(context, profile.contactCode!),
                const SizedBox(height: 14),
              ],

              // 5. Persona / Identities Card
              _buildPersonaCard(context, ref, profile),
              const SizedBox(height: 14),

              // 6. Navigation Shortcuts
              _buildShortcutsSection(context),
              const SizedBox(height: 18),

              // 7. Sign Out Action
              _buildSignOutTile(context, ref),
              const SizedBox(height: 36),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    UserProfile profile,
    AnonymousAvatarPreset preset,
  ) {
    final displayName = profile.displayName ?? '@${profile.username}';
    final bio = profile.bio;

    return AppCard(
      useGradient: true,
      hasGlow: true,
      padding: const EdgeInsets.all(20),
      onTap: () => context.push('/profile/edit'),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 76,
                height: 76,
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
                    preset.emoji,
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            displayName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryDark,
            ),
          ),
          if (profile.displayName != null) ...[
            const SizedBox(height: 2),
            Text(
              '@${profile.username}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.primaryLight,
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Online / Anonymity status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Online · Anonymous',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '"$bio"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 13,
                color: AppColors.textSecondaryDark,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow(Map<String, int> stats) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Chats',
            value: '${stats['chats'] ?? 0}',
            icon: Icons.chat_bubble_outline_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Saved',
            value: '${stats['bookmarks'] ?? 0}',
            icon: Icons.bookmark_border_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Days Active',
            value: '${stats['days'] ?? 1}',
            icon: Icons.calendar_today_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildInterestsSection(BuildContext context, UserProfile profile) {
    final interests = profile.interests;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.interests_rounded,
                    size: 18,
                    color: AppColors.primaryLight,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Your Interests',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => context.push('/profile/edit'),
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (interests.isEmpty)
            GestureDetector(
              onTap: () => context.push('/profile/edit'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.surfaceBorder,
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                      color: AppColors.primaryLight,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Add topics to match on shared interests',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMutedDark,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...interests.map(
                  (interest) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      interest,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.push('/profile/edit'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariantDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.surfaceBorder,
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 14,
                          color: AppColors.textMutedDark,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMutedDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildContactCodeCard(BuildContext context, String code) {
    final formatted = code.length == 8
        ? '${code.substring(0, 4)} - ${code.substring(4)}'
        : code;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.qr_code_rounded,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Anonymous Contact Code',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => ContactQrDialog(contactCode: code),
                  );
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Show QR',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceBorder, width: 0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatted,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.secondary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: AppColors.secondary,
                  tooltip: 'Copy Code',
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

  Widget _buildPersonaCard(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) {
    final activePersona = profile.persona ?? 'GhostRunner';

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.masks_rounded,
              color: AppColors.primaryLight,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active Persona',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMutedDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activePersona,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _showPersonaSwitcher(context, ref, profile),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.surfaceBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'Switch',
              style: TextStyle(fontSize: 12, color: AppColors.primaryLight),
            ),
          ),
        ],
      ),
    );
  }

  void _showPersonaSwitcher(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) {
    final defaultPersonas = [
      'GhostRunner',
      'NightCoder',
      'PixelFox',
      'VoidWalker',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Switch Anonymous Persona',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Personas allow you to chat with a different pseudonym while keeping your real account private.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMutedDark,
                ),
              ),
              const SizedBox(height: 16),
              ...defaultPersonas.map((name) {
                final isSelected = (profile.persona ?? 'GhostRunner') == name;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.fingerprint_rounded,
                    color: isSelected
                        ? AppColors.primaryLight
                        : AppColors.textMutedDark,
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primaryLight
                          : AppColors.textPrimaryDark,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.primaryLight,
                        )
                      : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await ref
                        .read(profileNotifierProvider.notifier)
                        .switchPersona(name);
                    if (context.mounted) {
                      context.showSnackBar('Switched persona to $name');
                    }
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShortcutsSection(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _ProfileMenuTile(
            icon: Icons.edit_note_rounded,
            title: 'Edit Profile',
            subtitle: 'Change display name, avatar, bio & topics',
            onTap: () => context.push('/profile/edit'),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.surfaceBorder),
          _ProfileMenuTile(
            icon: Icons.bookmark_border_rounded,
            title: 'Saved Messages',
            subtitle: 'Privately bookmarked chat messages',
            onTap: () => context.push('/profile/bookmarks'),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.surfaceBorder),
          _ProfileMenuTile(
            icon: Icons.shield_outlined,
            title: 'Privacy & Safety',
            subtitle: 'Who can message you, online status & receipts',
            onTap: () => context.push('/settings/privacy'),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.surfaceBorder),
          _ProfileMenuTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Dark theme, accent colors & chat bubbles',
            onTap: () => context.push('/settings/appearance'),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.surfaceBorder),
          _ProfileMenuTile(
            icon: Icons.lock_outline_rounded,
            title: 'Security',
            subtitle: 'Account credentials and session management',
            onTap: () => context.push('/settings/security'),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutTile(BuildContext context, WidgetRef ref) {
    return AppCard(
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryLight),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
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
