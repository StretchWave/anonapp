import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/profile_repository.dart';
import '../providers/profile_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _bioController;

  String _selectedAvatar = 'ghost';
  List<String> _selectedInterests = [];
  String? _selectedPersona;
  bool _isSaving = false;
  bool _initialized = false;

  static const List<String> _allAvailableInterests = [
    'Gaming',
    'Music',
    'Tech',
    'Coding',
    'Anime',
    'Movies',
    'Art',
    'Books',
    'Sports',
    'Philosophy',
    'Travel',
    'Science',
    'Fitness',
    'Food',
  ];

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _bioController = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initFieldsIfNeeded() {
    if (_initialized) return;
    final profile = ref.read(currentEnrichedProfileProvider).valueOrNull;
    if (profile != null) {
      _displayNameController.text = profile.displayName ?? '';
      _bioController.text = profile.bio ?? '';
      _selectedAvatar = profile.avatar ?? 'ghost';
      _selectedInterests = List.from(profile.interests);
      _selectedPersona = profile.persona;
      _initialized = true;
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await ref
          .read(profileNotifierProvider.notifier)
          .updateProfile(
            displayName: _displayNameController.text.trim().isEmpty
                ? null
                : _displayNameController.text.trim(),
            bio: _bioController.text.trim().isEmpty
                ? null
                : _bioController.text.trim(),
            avatar: _selectedAvatar,
            interests: _selectedInterests,
            persona: _selectedPersona,
          );

      if (mounted) {
        context.showSnackBar('Profile updated successfully!');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to update profile: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentEnrichedProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryLight,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile unavailable'));
          }

          _initFieldsIfNeeded();
          final preset = AnonymousAvatars.getPreset(_selectedAvatar);

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              children: [
                // Live Profile Preview Card
                _buildLivePreviewCard(profile, preset),
                const SizedBox(height: 22),

                // Section: Choose Avatar
                _buildSectionTitle('Choose Avatar', Icons.face_rounded),
                const SizedBox(height: 10),
                _buildAvatarGrid(),
                const SizedBox(height: 22),

                // Section: Public Details
                _buildSectionTitle('Anonymous Identity', Icons.badge_outlined),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _displayNameController,
                  label: 'Display Name (optional)',
                  hint: 'e.g. Night Stalker',
                  maxLength: 40,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _bioController,
                  label: 'Short Bio',
                  hint:
                      'Share a thought, favorite quote, or conversational vibe...',
                  maxLines: 3,
                  maxLength: 150,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 22),

                // Section: Interests
                _buildSectionTitle('Your Interests', Icons.interests_rounded),
                const SizedBox(height: 6),
                const Text(
                  'Select topics to help the Discover algorithm match you with like-minded anons.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMutedDark,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInterestsWrap(),
                const SizedBox(height: 32),

                AppButton(
                  text: 'Save Changes',
                  icon: Icons.check_circle_rounded,
                  isLoading: _isSaving,
                  onPressed: _save,
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLivePreviewCard(dynamic profile, AnonymousAvatarPreset preset) {
    final displayName = _displayNameController.text.trim();
    final bio = _bioController.text.trim();

    return AppCard(
      useGradient: true,
      hasGlow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                  boxShadow: AppColors.primaryGlow,
                ),
                alignment: Alignment.center,
                child: Text(preset.emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isNotEmpty
                          ? displayName
                          : '@${profile.username}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                    if (displayName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${profile.username}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      preset.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Preview',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMutedDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.surfaceBorder, width: 0.8),
              ),
              child: Text(
                '"$bio"',
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12.5,
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimaryDark,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AnonymousAvatars.presets.map((preset) {
        final isSelected = _selectedAvatar == preset.id;
        return GestureDetector(
          onTap: () => setState(() => _selectedAvatar = preset.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 74,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
                width: isSelected ? 1.8 : 1,
              ),
              boxShadow: isSelected ? AppColors.primaryGlow : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(preset.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(height: 4),
                Text(
                  preset.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primaryLight
                        : AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    int? maxLength,
    ValueChanged<String>? onChanged,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: onChanged,
        style: const TextStyle(
          color: AppColors.textPrimaryDark,
          fontSize: 14.5,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textMutedDark),
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppColors.textMutedDark,
            fontSize: 13,
          ),
          border: InputBorder.none,
          counterStyle: const TextStyle(
            fontSize: 11,
            color: AppColors.textMutedDark,
          ),
        ),
      ),
    );
  }

  Widget _buildInterestsWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allAvailableInterests.map((interest) {
        final isSelected = _selectedInterests.contains(interest);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedInterests.remove(interest);
              } else {
                _selectedInterests.add(interest);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  interest,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.primaryLight
                        : AppColors.textSecondaryDark,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
