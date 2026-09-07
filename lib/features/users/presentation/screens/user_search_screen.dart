import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import '../providers/user_search_provider.dart';

/// Screen for searching users by username or contact code.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startConversation(String otherUserId, String otherUsername) async {
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final convId = await repo.findOrCreateDirectConversation(otherUserId);

      // Refresh conversation list.
      ref.invalidate(conversationsProvider);

      if (mounted) {
        await context.push('/chat/$convId?username=$otherUsername');
      }
    } catch (e) {
      if (mounted) {
        final message = e is AppException
            ? e.message
            : 'Failed to start conversation.';
        context.showSnackBar(message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchResults = ref.watch(userSearchProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Users'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: 'Search by username or contact code...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
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
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_rounded,
                            size: 64,
                            color: theme.colorScheme.primary.withAlpha(102),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Search for users',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter a username (at least 3 characters) or '
                            'an 8-character contact code.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(153),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : searchResults.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (e, _) => Center(
                      child: Text(
                        e is AppException
                            ? e.message
                            : 'Search failed. Please try again.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    data: (users) {
                      if (users.isEmpty) {
                        return Center(
                          child: Text(
                            'No users found for "$_query".',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withAlpha(153),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: users.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = users[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withAlpha(51),
                              child: Text(
                                user.username[0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(
                              user.username,
                              style: theme.textTheme.titleMedium,
                            ),
                            subtitle: user.contactCode != null
                                ? Text(
                                    'Code: ${user.contactCode}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha(102),
                                    ),
                                  )
                                : null,
                            onTap: () => _startConversation(user.id, user.username),
                            trailing: IconButton(
                              icon: const Icon(Icons.chat_bubble_outline),
                              color: AppColors.primary,
                              onPressed: () =>
                                  _startConversation(user.id, user.username),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
