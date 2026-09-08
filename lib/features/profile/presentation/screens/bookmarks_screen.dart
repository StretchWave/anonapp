import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/bookmark_repository.dart';
import '../providers/bookmark_provider.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Saved Messages',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: bookmarksAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (err, _) => Center(child: Text('Error loading bookmarks: $err')),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.bookmark_border_rounded,
                        size: 36,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'No saved messages',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Long press on any chat message and tap "Bookmark" to keep it saved privately on this device.',
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
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: bookmarks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = bookmarks[index];
              return _BookmarkItemCard(bookmark: item);
            },
          );
        },
      ),
    );
  }
}

class _BookmarkItemCard extends ConsumerWidget {
  const _BookmarkItemCard({required this.bookmark});

  final BookmarkedMessage bookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        context.push(
          '/chat/${bookmark.conversationId}?username=${bookmark.senderUsername}',
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '@${bookmark.senderUsername}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    bookmark.createdAt.shortTime,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_remove_rounded, size: 20),
                color: AppColors.textMutedDark,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () async {
                  await ref
                      .read(bookmarksProvider.notifier)
                      .toggleBookmark(bookmark);
                  if (context.mounted) {
                    context.showSnackBar('Message removed from bookmarks.');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bookmark.content,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.textSecondaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
