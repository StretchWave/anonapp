import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../profile/presentation/providers/safety_provider.dart';

class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(privacySettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy & Safety',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: settingsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (settings) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildSectionHeader('Discovery & Connection'),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _buildSwitchTile(
                      title: 'Allow Matching in Discover',
                      subtitle:
                          'Permit the discovery engine to match you with anons sharing your topics.',
                      value: settings.allowMatching,
                      onChanged: (val) {
                        ref
                            .read(privacySettingsProvider.notifier)
                            .updateSettings(
                              settings.copyWith(allowMatching: val),
                            );
                        context.showSnackBar('Privacy setting updated.');
                      },
                    ),
                    const Divider(
                      height: 1,
                      indent: 16,
                      color: AppColors.surfaceBorder,
                    ),
                    _buildSwitchTile(
                      title: 'Allow Contact Code Discovery',
                      subtitle:
                          'Allow others to connect with you when they enter your 8-digit code.',
                      value: settings.allowContactCodeDiscovery,
                      onChanged: (val) {
                        ref
                            .read(privacySettingsProvider.notifier)
                            .updateSettings(
                              settings.copyWith(allowContactCodeDiscovery: val),
                            );
                        context.showSnackBar('Privacy setting updated.');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _buildSectionHeader('Presence & Chat Indicators'),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _buildSwitchTile(
                      title: 'Show Online Status',
                      subtitle:
                          'Display a green online indicator when you are using AnonApp.',
                      value: settings.showOnlineStatus,
                      onChanged: (val) {
                        ref
                            .read(privacySettingsProvider.notifier)
                            .updateSettings(
                              settings.copyWith(showOnlineStatus: val),
                            );
                        context.showSnackBar('Privacy setting updated.');
                      },
                    ),
                    const Divider(
                      height: 1,
                      indent: 16,
                      color: AppColors.surfaceBorder,
                    ),
                    _buildSwitchTile(
                      title: 'Read Receipts',
                      subtitle:
                          'Show blue/teal status ticks when you have read incoming messages.',
                      value: settings.readReceipts,
                      onChanged: (val) {
                        ref
                            .read(privacySettingsProvider.notifier)
                            .updateSettings(
                              settings.copyWith(readReceipts: val),
                            );
                        context.showSnackBar('Privacy setting updated.');
                      },
                    ),
                    const Divider(
                      height: 1,
                      indent: 16,
                      color: AppColors.surfaceBorder,
                    ),
                    _buildSwitchTile(
                      title: 'Typing Indicator',
                      subtitle:
                          'Let others see when you are actively composing a reply.',
                      value: settings.typingIndicator,
                      onChanged: (val) {
                        ref
                            .read(privacySettingsProvider.notifier)
                            .updateSettings(
                              settings.copyWith(typingIndicator: val),
                            );
                        context.showSnackBar('Privacy setting updated.');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _buildSectionHeader('Who Can Message Me'),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      onTap: () {
                        ref
                            .read(privacySettingsProvider.notifier)
                            .updateSettings(
                              settings.copyWith(whoCanMessage: 'everyone'),
                            );
                        context.showSnackBar('Messaging rule updated.');
                      },
                      leading: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: settings.whoCanMessage == 'everyone'
                                ? AppColors.primaryLight
                                : AppColors.textMutedDark,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: settings.whoCanMessage == 'everyone'
                            ? Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primaryLight,
                                ),
                              )
                            : null,
                      ),
                      title: const Text(
                        'Everyone',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                      subtitle: const Text(
                        'Any anon found through Discover or search can send you a message.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMutedDark,
                        ),
                      ),
                    ),
                    const Divider(
                      height: 1,
                      indent: 16,
                      color: AppColors.surfaceBorder,
                    ),
                    ListTile(
                      onTap: () {
                        ref
                            .read(privacySettingsProvider.notifier)
                            .updateSettings(
                              settings.copyWith(whoCanMessage: 'contacts_only'),
                            );
                        context.showSnackBar('Messaging rule updated.');
                      },
                      leading: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: settings.whoCanMessage == 'contacts_only'
                                ? AppColors.primaryLight
                                : AppColors.textMutedDark,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: settings.whoCanMessage == 'contacts_only'
                            ? Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primaryLight,
                                ),
                              )
                            : null,
                      ),
                      title: const Text(
                        'Only With Contact Code',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                      subtitle: const Text(
                        'Only anons who enter your private 8-digit contact code can message you.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMutedDark,
                        ),
                      ),
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

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primaryLight,
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
    );
  }
}
