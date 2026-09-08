import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarkedMessage {
  const BookmarkedMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderUsername,
    required this.content,
    required this.isImage,
    required this.createdAt,
    required this.bookmarkedAt,
  });

  factory BookmarkedMessage.fromJson(Map<String, dynamic> json) =>
      BookmarkedMessage(
        messageId: json['message_id'] as String,
        conversationId: json['conversation_id'] as String,
        senderUsername: json['sender_username'] as String? ?? 'Anon',
        content: json['content'] as String,
        isImage: json['is_image'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        bookmarkedAt: DateTime.parse(json['bookmarked_at'] as String),
      );

  final String messageId;
  final String conversationId;
  final String senderUsername;
  final String content;
  final bool isImage;
  final DateTime createdAt;
  final DateTime bookmarkedAt;

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'conversation_id': conversationId,
    'sender_username': senderUsername,
    'content': content,
    'is_image': isImage,
    'created_at': createdAt.toIso8601String(),
    'bookmarked_at': bookmarkedAt.toIso8601String(),
  };
}

/// Repository for storing and retrieving user's saved/bookmarked messages.
class BookmarkRepository {
  String _key(String userId) => 'anon_bookmarks_$userId';

  Future<List<BookmarkedMessage>> getBookmarks(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (e) =>
                BookmarkedMessage.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList()
        ..sort((a, b) => b.bookmarkedAt.compareTo(a.bookmarkedAt));
    } catch (e) {
      debugPrint('Error getting bookmarks: $e');
      return const [];
    }
  }

  Future<bool> isBookmarked(String userId, String messageId) async {
    final list = await getBookmarks(userId);
    return list.any((b) => b.messageId == messageId);
  }

  Future<bool> toggleBookmark(String userId, BookmarkedMessage bookmark) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getBookmarks(userId);
    final exists = list.any((b) => b.messageId == bookmark.messageId);

    List<BookmarkedMessage> updated;
    if (exists) {
      updated = list.where((b) => b.messageId != bookmark.messageId).toList();
    } else {
      updated = [bookmark, ...list];
    }

    await prefs.setString(
      _key(userId),
      jsonEncode(updated.map((b) => b.toJson()).toList()),
    );
    return !exists; // returns true if now bookmarked, false if unbookmarked
  }
}
