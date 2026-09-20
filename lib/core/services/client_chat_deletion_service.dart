import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for [ClientChatDeletionService].
final clientChatDeletionServiceProvider =
    Provider<ClientChatDeletionService>((ref) {
      return ClientChatDeletionService.instance;
    });

/// Service managing client-sided chat deletion ("Delete for me").
/// Stores deletion timestamps in SharedPreferences keyed by user ID so that
/// deleting a chat removes it for the current user while preserving the
/// conversation and messages for the other participant.
class ClientChatDeletionService {
  ClientChatDeletionService._();

  static final ClientChatDeletionService instance =
      ClientChatDeletionService._();

  String _prefKey(String userId) => 'anon_client_deleted_chats_$userId';

  /// Mark a conversation as deleted for [userId] as of [timestamp] (defaults to now).
  Future<void> markConversationDeleted({
    required String userId,
    required String conversationId,
    DateTime? timestamp,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = await getDeletedConversations(userId);
      final deleteTime = (timestamp ?? DateTime.now()).toUtc();
      map[conversationId] = deleteTime;

      final encoded = jsonEncode({
        for (final entry in map.entries) entry.key: entry.value.toIso8601String(),
      });
      await prefs.setString(_prefKey(userId), encoded);
    } catch (e) {
      debugPrint('[ClientChatDeletionService] Error saving deletion: $e');
    }
  }

  /// Retrieves all deleted conversation IDs and their deletion timestamps for [userId].
  Future<Map<String, DateTime>> getDeletedConversations(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey(userId));
      if (raw == null || raw.isEmpty) return <String, DateTime>{};

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, DateTime>{};

      final result = <String, DateTime>{};
      for (final entry in decoded.entries) {
        final key = entry.key as String;
        final valStr = entry.value as String?;
        if (valStr != null) {
          final dt = DateTime.tryParse(valStr);
          if (dt != null) {
            result[key] = dt;
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('[ClientChatDeletionService] Error reading deleted conversations: $e');
      return <String, DateTime>{};
    }
  }

  /// Returns the deletion timestamp for a specific conversation, or null if not deleted.
  Future<DateTime?> getDeletionTimestamp({
    required String userId,
    required String conversationId,
  }) async {
    final map = await getDeletedConversations(userId);
    return map[conversationId];
  }

  /// Restores a conversation (e.g. if the user explicitly clears deletion or undoes).
  Future<void> restoreConversation({
    required String userId,
    required String conversationId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = await getDeletedConversations(userId);
      if (map.containsKey(conversationId)) {
        map.remove(conversationId);
        final encoded = jsonEncode({
          for (final entry in map.entries)
            entry.key: entry.value.toIso8601String(),
        });
        await prefs.setString(_prefKey(userId), encoded);
      }
    } catch (e) {
      debugPrint('[ClientChatDeletionService] Error restoring conversation: $e');
    }
  }

  /// Clears all recorded client deletions for a user.
  Future<void> clearAllDeleted(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey(userId));
    } catch (e) {
      debugPrint('[ClientChatDeletionService] Error clearing all deleted: $e');
    }
  }
}
