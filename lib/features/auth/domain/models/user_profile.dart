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
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      contactCode: json['contact_code'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? contactCode;
  final DateTime createdAt;
  final DateTime? lastSeen;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'contact_code': contactCode,
      'created_at': createdAt.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? username,
    String? displayName,
    String? contactCode,
    DateTime? createdAt,
    DateTime? lastSeen,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      contactCode: contactCode ?? this.contactCode,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
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
          lastSeen == other.lastSeen;

  @override
  int get hashCode => Object.hash(
        id,
        username,
        displayName,
        contactCode,
        createdAt,
        lastSeen,
      );

  @override
  String toString() => 'UserProfile(id: $id, username: $username)';
}
