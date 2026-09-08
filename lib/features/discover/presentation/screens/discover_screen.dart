import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import '../../../users/presentation/providers/user_search_provider.dart';

class DiscoverTopic {
  const DiscoverTopic({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorHex,
  });

  final String id;
  final String name;
  final String emoji;
  final int colorHex;
}

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _searchController;
  late AnimationController _orbitalController;

  String _searchQuery = '';
  String? _selectedIntent = 'Just Chat';
  String? _selectedTopic = 'Gaming';
  bool _isMatching = false;
  String _matchingStatus = 'Scanning for compatible anons...';

  static const List<String> _intents = [
    'Just Chat',
    'Need Advice',
    'Gaming',
    'Deep Talk',
    'Looking for Friends',
    'Talk Tech',
    'Random',
  ];

  static const List<DiscoverTopic> _topics = [
    DiscoverTopic(
      id: 'gaming',
      name: 'Gaming',
      emoji: '🎮',
      colorHex: 0xFF6C5CE7,
    ),
    DiscoverTopic(
      id: 'music',
      name: 'Music',
      emoji: '🎵',
      colorHex: 0xFFFD79A8,
    ),
    DiscoverTopic(
      id: 'coding',
      name: 'Coding',
      emoji: '💻',
      colorHex: 0xFF00D9A6,
    ),
    DiscoverTopic(
      id: 'anime',
      name: 'Anime',
      emoji: '⛩️',
      colorHex: 0xFFFF7675,
    ),
    DiscoverTopic(
      id: 'movies',
      name: 'Movies',
      emoji: '🎬',
      colorHex: 0xFFFDCB6E,
    ),
    DiscoverTopic(id: 'art', name: 'Art', emoji: '🎨', colorHex: 0xFFA29BFE),
    DiscoverTopic(
      id: 'books',
      name: 'Books',
      emoji: '📚',
      colorHex: 0xFF74B9FF,
    ),
    DiscoverTopic(
      id: 'sports',
      name: 'Sports',
      emoji: '⚽',
      colorHex: 0xFF55EFC4,
    ),
    DiscoverTopic(id: 'tech', name: 'Tech', emoji: '🚀', colorHex: 0xFF968AF0),
    DiscoverTopic(
      id: 'philosophy',
      name: 'Philosophy',
      emoji: '💭',
      colorHex: 0xFFE17055,
    ),
    DiscoverTopic(
      id: 'travel',
      name: 'Travel',
      emoji: '✈️',
      colorHex: 0xFF0984E3,
    ),
    DiscoverTopic(
      id: 'science',
      name: 'Science',
      emoji: '🧪',
      colorHex: 0xFF00CEC9,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _orbitalController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _orbitalController.dispose();
    super.dispose();
  }

  Future<void> _startMatching({String? topic, bool isRandom = false}) async {
    if (_isMatching) return;

    setState(() {
      _isMatching = true;
      _selectedTopic = topic ?? _selectedTopic;
      _matchingStatus = isRandom
          ? 'Connecting you to a random anon...'
          : 'Scanning for anons interested in ${_selectedTopic ?? "chats"}...';
    });

    unawaited(_orbitalController.repeat());

    try {
      // Step 1: Wait 1.8s for smooth radar/orbital immersion
      await Future.delayed(const Duration(milliseconds: 1800));

      if (!mounted) return;
      setState(() {
        _matchingStatus = 'Checking shared interests & compatibility...';
      });
      await Future.delayed(const Duration(milliseconds: 1000));

      // Step 2: Query candidate pool using random alphabet seed
      final randChar = String.fromCharCode(97 + Random().nextInt(26));
      final candidates = await ref.read(userSearchProvider(randChar).future);

      if (candidates.isNotEmpty && mounted) {
        final match = candidates[Random().nextInt(candidates.length)];
        setState(() {
          _matchingStatus = 'Match found with an anon! Connecting...';
        });
        await Future.delayed(const Duration(milliseconds: 600));
        await _openChatWithUser(match.id, match.username);
      } else if (mounted) {
        context.showSnackBar(
          'No compatible anons online right now. Try another topic or direct search!',
        );
      }
    } catch (_) {
      if (mounted) {
        context.showSnackBar('Matching interrupted. Please try again.');
      }
    } finally {
      if (mounted) {
        _orbitalController.stop();
        _orbitalController.reset();
        setState(() => _isMatching = false);
      }
    }
  }

  Future<void> _openChatWithUser(String userId, String username) async {
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final convId = await repo.findOrCreateDirectConversation(userId);
      ref.invalidate(conversationsProvider);

      if (mounted) {
        await context.push('/chat/$convId?username=$username');
      }
    } catch (e) {
      if (mounted) {
        final msg = e is AppException
            ? e.message
            : 'Could not connect to anon.';
        context.showSnackBar(msg, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Discover',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // 1. Search Bar (Search by @username or 8-char contact code)
              _buildSearchBar(),
              const SizedBox(height: 16),

              // If active search query, show results directly
              if (_searchQuery.isNotEmpty) ...[
                _buildSearchResults(),
              ] else ...[
                // 2. MATCH ME Hero Card
                _buildMatchMeCard(),
                const SizedBox(height: 16),

                // 3. RANDOM CHAT Quick Card
                _buildRandomChatCard(),
                const SizedBox(height: 20),

                // 4. BROWSE TOPICS Section
                _buildTopicsSection(),
                const SizedBox(height: 36),
              ],
            ],
          ),

          // Matching Overlay
          if (_isMatching) _buildMatchingOverlay(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: AppColors.textMutedDark,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(
                color: AppColors.textPrimaryDark,
                fontSize: 14.5,
              ),
              decoration: const InputDecoration(
                hintText: 'Search @username or 8-char contact code...',
                hintStyle: TextStyle(
                  color: AppColors.textMutedDark,
                  fontSize: 13.5,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              color: AppColors.textMutedDark,
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMatchMeCard() {
    return AppCard(
      useGradient: true,
      hasGlow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.primaryLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Match Me',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  Text(
                    'Find an anon with shared conversation intent',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Conversation Intent Chips
          const Text(
            'Conversation Intent (Optional):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryDark,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _intents.map((intent) {
                final isSelected = _selectedIntent == intent;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedIntent = intent),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryLight
                              : AppColors.surfaceBorder,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        intent,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.primaryLight
                              : AppColors.textMutedDark,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          AppButton(
            text: 'Find Match',
            icon: Icons.radar_rounded,
            variant: AppButtonVariant.primary,
            onPressed: () => _startMatching(topic: _selectedTopic),
          ),
        ],
      ),
    );
  }

  Widget _buildRandomChatCard() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _startMatching(isRandom: true),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shuffle_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Random Chat',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Start a completely random conversation instantly',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMutedDark,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildTopicsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.category_outlined,
              size: 18,
              color: AppColors.primaryLight,
            ),
            SizedBox(width: 8),
            Text(
              'Browse Topics',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimaryDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap any topic to discover anons interested in talking about it.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMutedDark),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: _topics.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, index) {
            final topic = _topics[index];
            return GestureDetector(
              onTap: () => _startMatching(topic: topic.name),
              child: AppCard(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(topic.emoji, style: const TextStyle(fontSize: 26)),
                    const SizedBox(height: 6),
                    Text(
                      topic.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final searchAsync = ref.watch(userSearchProvider(_searchQuery));

    return searchAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (users) {
        if (users.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 48,
                    color: AppColors.textMutedDark,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No anons matching "$_searchQuery"',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Try another username or enter an exact 8-character contact code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final user = users[index];
            final initial = user.username.isNotEmpty
                ? user.username[0].toUpperCase()
                : '?';

            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              onTap: () => _openChatWithUser(user.id, user.username),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName ?? '@${user.username}',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryDark,
                          ),
                        ),
                        if (user.displayName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '@${user.username}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: AppColors.primaryLight,
                    size: 20,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMatchingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Orbital Animation
              AnimatedBuilder(
                animation: _orbitalController,
                builder: (context, child) {
                  final angle = _orbitalController.value * 2 * pi;
                  const radius = 64.0;
                  final x = radius * cos(angle);
                  final y = radius * sin(angle);

                  return SizedBox(
                    width: 180,
                    height: 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer orbit ring
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // Pulsing inner aura
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        // Center Core Avatar
                        Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: AppColors.primaryGlow,
                          ),
                          child: const Icon(
                            Icons.radar_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        // Orbiting particle
                        Transform.translate(
                          offset: Offset(x, y),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.secondary,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.8,
                                  ),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              Text(
                _matchingStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryDark,
                ),
              ),
              const SizedBox(height: 8),

              if (_selectedIntent != null)
                Text(
                  'Intent: $_selectedIntent',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.secondary,
                  ),
                ),
              const SizedBox(height: 28),

              OutlinedButton(
                onPressed: () {
                  _orbitalController.stop();
                  _orbitalController.reset();
                  setState(() => _isMatching = false);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.surfaceBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Cancel Search',
                  style: TextStyle(color: AppColors.textMutedDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
