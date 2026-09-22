import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/services/presence/presence_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import '../providers/user_search_provider.dart';

enum SearchTab { match, direct }

/// Redesigned user discovery and search screen with interest-based matching
/// and direct handle/contact code search.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen>
    with SingleTickerProviderStateMixin {
  SearchTab _currentTab = SearchTab.match;

  // Direct Search state
  final _searchController = TextEditingController();
  String _query = '';

  // Discovery / Match state
  final Set<String> _selectedInterests = {};
  bool _isMatching = false;
  late AnimationController _radarController;

  static const List<Map<String, String>> _availableInterests = [
    {'name': 'Music', 'icon': '🎵'},
    {'name': 'Gaming', 'icon': '🎮'},
    {'name': 'Movies', 'icon': '🎬'},
    {'name': 'Tech', 'icon': '💻'},
    {'name': 'Anime', 'icon': '🍙'},
    {'name': 'Art', 'icon': '🎨'},
    {'name': 'Books', 'icon': '📚'},
    {'name': 'Sports', 'icon': '⚽'},
    {'name': 'Travel', 'icon': '✈️'},
    {'name': 'Food', 'icon': '🍕'},
    {'name': 'Cybersec', 'icon': '🔒'},
    {'name': 'Philosophy', 'icon': '🧠'},
    {'name': 'Photography', 'icon': '📷'},
    {'name': 'Startups', 'icon': '🚀'},
  ];

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  void _toggleInterest(String interest) {
    setState(() {
      if (_selectedInterests.contains(interest)) {
        _selectedInterests.remove(interest);
      } else {
        _selectedInterests.add(interest);
      }
    });
  }

  Future<void> _startMatching() async {
    if (_selectedInterests.isEmpty) return;

    setState(() => _isMatching = true);
    unawaited(_radarController.repeat());

    try {
      // Simulate radar scanning delay for immersive UX
      await Future.delayed(const Duration(milliseconds: 2200));

      // Query for an available user to match with
      final randChar = String.fromCharCode(97 + Random().nextInt(26));
      final candidates = await ref.read(userSearchProvider(randChar).future);

      if (candidates.isNotEmpty && mounted) {
        final match = candidates[Random().nextInt(candidates.length)];
        await _startConversation(match.id, match.username);
      } else if (mounted) {
        context.showSnackBar(
          'No available anons matching right now. Try another interest or direct search!',
        );
      }
    } catch (_) {
      if (mounted) {
        context.showSnackBar(
          'Matching service timed out. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        _radarController.stop();
        _radarController.reset();
        setState(() => _isMatching = false);
      }
    }
  }

  Future<void> _startConversation(
    String otherUserId,
    String otherUsername,
  ) async {
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final convId = await repo.findOrCreateDirectConversation(otherUserId);

      // Refresh conversations list.
      ref.invalidate(conversationsProvider);

      if (mounted) {
        await context.push(
          '/chat/$convId?username=$otherUsername&otherUserId=$otherUserId',
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is AppException
            ? e.message
            : 'Failed to connect to conversation.';
        context.showSnackBar(message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Discover & Search',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: Column(
        children: [
          // Segmented Switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceBorder, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      title: 'Match by Topics',
                      icon: Icons.auto_awesome_rounded,
                      tab: SearchTab.match,
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      title: 'Direct Search',
                      icon: Icons.person_search_rounded,
                      tab: SearchTab.direct,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Body Views
          Expanded(
            child: _currentTab == SearchTab.match
                ? (_isMatching ? _buildMatchingRadar() : _buildInterestsView())
                : _buildDirectSearchView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required SearchTab tab,
  }) {
    final isSelected = _currentTab == tab;

    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceVariantDark : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: AppColors.surfaceBorderGlow, width: 1)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? AppColors.primaryLight
                  : AppColors.textMutedDark,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? AppColors.textPrimaryDark
                    : AppColors.textMutedDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Match by Interests View ─────────────────────────────────────
  Widget _buildInterestsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header card
          AppCard(
            useGradient: true,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Interest Matching',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pick topics to connect with like-minded anons.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Select Topics',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondaryDark,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),

          // Chips Wrap
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _availableInterests.map((interest) {
              final name = interest['name']!;
              final emoji = interest['icon']!;
              final isSelected = _selectedInterests.contains(name);

              return GestureDetector(
                onTap: () => _toggleInterest(name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withAlpha(45)
                        : AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryLight
                          : AppColors.surfaceBorder,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    boxShadow: isSelected ? AppColors.primaryGlow : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondaryDark,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: AppColors.primaryLight,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 36),

          // Matching action button
          AppButton(
            text: _selectedInterests.isEmpty
                ? 'Select at least 1 topic'
                : 'Find Anonymous Match (${_selectedInterests.length})',
            icon: Icons.radar_rounded,
            onPressed: _selectedInterests.isEmpty ? null : _startMatching,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Matching Radar Animation ────────────────────────────────────
  Widget _buildMatchingRadar() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Radar ring 1
                    Container(
                      width: 160 * (0.4 + (_radarController.value * 0.6)),
                      height: 160 * (0.4 + (_radarController.value * 0.6)),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(
                            alpha: (1.0 - _radarController.value).clamp(
                              0.0,
                              1.0,
                            ),
                          ),
                          width: 1.5,
                        ),
                      ),
                    ),
                    // Radar ring 2
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withAlpha(35),
                      ),
                    ),
                    // Core Icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: AppColors.primaryGlow,
                      ),
                      child: const Icon(
                        Icons.radar_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'Scanning for anons...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Searching for active conversations in ${_selectedInterests.join(', ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Direct Search View ──────────────────────────────────────────
  Widget _buildDirectSearchView() {
    final searchResults = ref.watch(userSearchProvider(_query));

    return Column(
      children: [
        // Search Input Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value.trim()),
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimaryDark,
            ),
            decoration: InputDecoration(
              hintText: 'Search username or 8-char contact code...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textMutedDark,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: AppColors.textMutedDark,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
          ),
        ),

        // Results
        Expanded(
          child: _query.length < 3
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surfaceBorder,
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_search_rounded,
                            size: 48,
                            color: AppColors.primaryLight,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Direct Lookup',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Enter at least 3 letters of a username or a recipient\'s 8-character contact code.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textMutedDark,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : searchResults.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      e is AppException
                          ? e.message
                          : 'Search failed. Please try again.',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                  data: (users) {
                    if (users.isEmpty) {
                      return Center(
                        child: Text(
                          'No users found matching "$_query".',
                          style: const TextStyle(
                            color: AppColors.textMutedDark,
                            fontSize: 14,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: users.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final initial = user.username.isNotEmpty
                            ? user.username[0].toUpperCase()
                            : '?';

                        final isUserOnline = ref.watch(
                          isUserOnlineProvider(user.id),
                        );

                        return AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppColors.primary
                                        .withAlpha(40),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: AppColors.primaryLight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isUserOnline
                                            ? AppColors.online
                                            : AppColors.offline,
                                        border: Border.all(
                                          color: AppColors.surfaceDark,
                                          width: 2,
                                        ),
                                        boxShadow: isUserOnline
                                            ? [
                                                BoxShadow(
                                                  color: AppColors.online
                                                      .withValues(alpha: 0.6),
                                                  blurRadius: 4,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '@${user.username}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimaryDark,
                                      ),
                                    ),
                                    if (user.displayName != null &&
                                        user.displayName!.isNotEmpty)
                                      Text(
                                        user.displayName!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMutedDark,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              AppButton(
                                text: 'Chat',
                                icon: Icons.chat_bubble_outline_rounded,
                                width: 90,
                                height: 38,
                                variant: AppButtonVariant.primary,
                                onPressed: () =>
                                    _startConversation(user.id, user.username),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
