import 'package:flutter/foundation.dart';

/// Represents a user's public profile from the `profiles` table.
///
/// This is what other users see — never contains email, password, or auth
/// internals.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.contactCode,
    required this.createdAt,
    this.lastSeen,
    this.bio,
    this.avatar,
    this.interests = const [],
    this.persona,
    this.onlineStatusVisible = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    List<String> parsedInterests = const [];
    if (json['interests'] is List) {
      parsedInterests = (json['interests'] as List)
          .map((e) => e.toString())
          .toList(growable: false);
    }

    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      contactCode: json['contact_code'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      bio: json['bio'] as String?,
      avatar: json['avatar'] as String?,
      interests: parsedInterests,
      persona: json['persona'] as String?,
      onlineStatusVisible: json['online_status_visible'] as bool? ?? true,
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? contactCode;
  final DateTime createdAt;
  final DateTime? lastSeen;
  final String? bio;
  final String? avatar;
  final List<String> interests;
  final String? persona;
  final bool onlineStatusVisible;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'contact_code': contactCode,
      'created_at': createdAt.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
      'bio': bio,
      'avatar': avatar,
      'interests': interests,
      'persona': persona,
      'online_status_visible': onlineStatusVisible,
    };
  }

  UserProfile copyWith({
    String? id,
    String? username,
    String? displayName,
    String? contactCode,
    DateTime? createdAt,
    DateTime? lastSeen,
    String? bio,
    String? avatar,
    List<String>? interests,
    String? persona,
    bool? onlineStatusVisible,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      contactCode: contactCode ?? this.contactCode,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      bio: bio ?? this.bio,
      avatar: avatar ?? this.avatar,
      interests: interests ?? this.interests,
      persona: persona ?? this.persona,
      onlineStatusVisible: onlineStatusVisible ?? this.onlineStatusVisible,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          username == other.username &&
          displayName == other.displayName &&
          contactCode == other.contactCode &&
          createdAt == other.createdAt &&
          lastSeen == other.lastSeen &&
          bio == other.bio &&
          avatar == other.avatar &&
          listEquals(interests, other.interests) &&
          persona == other.persona &&
          onlineStatusVisible == other.onlineStatusVisible;

  @override
  int get hashCode => Object.hash(
    id,
    username,
    displayName,
    contactCode,
    createdAt,
    lastSeen,
    bio,
    avatar,
    Object.hashAll(interests),
    persona,
    onlineStatusVisible,
  );

  @override
  String toString() => 'UserProfile(id: $id, username: $username)';
}
