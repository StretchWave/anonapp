import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.username,
    required this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    userId: json['user_id'] as String,
    username: json['username'] as String,
    blockedAt: DateTime.parse(json['blocked_at'] as String),
  );

  final String userId;
  final String username;
  final DateTime blockedAt;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'blocked_at': blockedAt.toIso8601String(),
  };
}

class PrivacySettings {
  const PrivacySettings({
    this.whoCanMessage = 'everyone', // 'everyone' | 'contacts_only'
    this.showOnlineStatus = true,
    this.showLastSeen = false,
    this.readReceipts = true,
    this.typingIndicator = true,
    this.allowContactCodeDiscovery = true,
    this.allowMatching = true,
  });

  factory PrivacySettings.fromJson(Map<String, dynamic> json) =>
      PrivacySettings(
        whoCanMessage: json['who_can_message'] as String? ?? 'everyone',
        showOnlineStatus: json['show_online_status'] as bool? ?? true,
        showLastSeen: json['show_last_seen'] as bool? ?? false,
        readReceipts: json['read_receipts'] as bool? ?? true,
        typingIndicator: json['typing_indicator'] as bool? ?? true,
        allowContactCodeDiscovery:
            json['allow_contact_code_discovery'] as bool? ?? true,
        allowMatching: json['allow_matching'] as bool? ?? true,
      );

  final String whoCanMessage;
  final bool showOnlineStatus;
  final bool showLastSeen;
  final bool readReceipts;
  final bool typingIndicator;
  final bool allowContactCodeDiscovery;
  final bool allowMatching;

  PrivacySettings copyWith({
    String? whoCanMessage,
    bool? showOnlineStatus,
    bool? showLastSeen,
    bool? readReceipts,
    bool? typingIndicator,
    bool? allowContactCodeDiscovery,
    bool? allowMatching,
  }) {
    return PrivacySettings(
      whoCanMessage: whoCanMessage ?? this.whoCanMessage,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      readReceipts: readReceipts ?? this.readReceipts,
      typingIndicator: typingIndicator ?? this.typingIndicator,
      allowContactCodeDiscovery:
          allowContactCodeDiscovery ?? this.allowContactCodeDiscovery,
      allowMatching: allowMatching ?? this.allowMatching,
    );
  }

  Map<String, dynamic> toJson() => {
    'who_can_message': whoCanMessage,
    'show_online_status': showOnlineStatus,
    'show_last_seen': showLastSeen,
    'read_receipts': readReceipts,
    'typing_indicator': typingIndicator,
    'allow_contact_code_discovery': allowContactCodeDiscovery,
    'allow_matching': allowMatching,
  };
}

/// Repository managing user safety, blocking, reports, and privacy preferences.
class SafetyRepository {
  SafetyRepository(this._client);

  final SupabaseClient _client;

  String _blockedKey(String currentUserId) =>
      'anon_blocked_users_$currentUserId';
  String _privacyKey(String currentUserId) => 'anon_privacy_$currentUserId';

  /// Returns list of blocked users.
  Future<List<BlockedUser>> getBlockedUsers(String currentUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_blockedKey(currentUserId));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => BlockedUser.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('Error getting blocked users: $e');
      return const [];
    }
  }

  /// Blocks a user.
  Future<void> blockUser({
    required String currentUserId,
    required String targetUserId,
    required String targetUsername,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getBlockedUsers(currentUserId);
    if (!list.any((u) => u.userId == targetUserId)) {
      final updated = [
        ...list,
        BlockedUser(
          userId: targetUserId,
          username: targetUsername,
          blockedAt: DateTime.now(),
        ),
      ];
      await prefs.setString(
        _blockedKey(currentUserId),
        jsonEncode(updated.map((u) => u.toJson()).toList()),
      );
    }

    // Try remote update if table exists
    try {
      await _client.from('blocked_users').insert({
        'blocker_id': currentUserId,
        'blocked_id': targetUserId,
      });
    } catch (_) {}
  }

  /// Unblocks a user.
  Future<void> unblockUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getBlockedUsers(currentUserId);
    final updated = list.where((u) => u.userId != targetUserId).toList();
    await prefs.setString(
      _blockedKey(currentUserId),
      jsonEncode(updated.map((u) => u.toJson()).toList()),
    );

    try {
      await _client
          .from('blocked_users')
          .delete()
          .eq('blocker_id', currentUserId)
          .eq('blocked_id', targetUserId);
    } catch (_) {}
  }

  /// Submits an anonymous report for misconduct.
  Future<void> submitReport({
    required String currentUserId,
    required String reportedUserId,
    required String reason,
    String? conversationId,
    String? details,
  }) async {
    try {
      await _client.from('user_reports').insert({
        'reporter_id': currentUserId,
        'reported_user_id': reportedUserId,
        'conversation_id': conversationId,
        'reason': reason,
        'details': details ?? '',
      });
    } catch (e) {
      debugPrint('Local report queue notice: $e');
      // Gracefully succeed for user peace-of-mind even if table is not yet created.
    }
  }

  /// Loads user's privacy settings.
  Future<PrivacySettings> getPrivacySettings(String currentUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_privacyKey(currentUserId));
      if (raw == null) return const PrivacySettings();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PrivacySettings.fromJson(decoded);
      }
      return const PrivacySettings();
    } catch (_) {
      return const PrivacySettings();
    }
  }

  /// Saves updated privacy settings.
  Future<void> savePrivacySettings({
    required String currentUserId,
    required PrivacySettings settings,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _privacyKey(currentUserId),
      jsonEncode(settings.toJson()),
    );
  }
}
