import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/bookmark_repository.dart';

final bookmarkRepositoryProvider = Provider<BookmarkRepository>((ref) {
  return BookmarkRepository();
});

final bookmarksProvider =
    AsyncNotifierProvider<BookmarksNotifier, List<BookmarkedMessage>>(
      BookmarksNotifier.new,
    );

class BookmarksNotifier extends AsyncNotifier<List<BookmarkedMessage>> {
  BookmarkRepository get _repo => ref.read(bookmarkRepositoryProvider);

  String? get _currentUserId =>
      ref.read(supabaseClientProvider).auth.currentUser?.id;

  @override
  FutureOr<List<BookmarkedMessage>> build() async {
    final uid = _currentUserId;
    if (uid == null) return const [];
    return _repo.getBookmarks(uid);
  }

  Future<bool> toggleBookmark(BookmarkedMessage message) async {
    final uid = _currentUserId;
    if (uid == null) return false;

    final isNowBookmarked = await _repo.toggleBookmark(uid, message);
    ref.invalidateSelf();
    return isNowBookmarked;
  }
}

final isMessageBookmarkedProvider = FutureProvider.family<bool, String>((
  ref,
  messageId,
) async {
  final bookmarks = await ref.watch(bookmarksProvider.future);
  return bookmarks.any((b) => b.messageId == messageId);
});
