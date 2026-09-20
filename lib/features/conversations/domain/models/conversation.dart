/// Represents a conversation with its metadata and the other member's info.
class Conversation {
  const Conversation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.disappearingMessagesDuration,
    this.otherMemberUsername,
    this.otherMemberId,
    this.otherMemberLastSeen,
    this.lastMessageContent,
    this.lastMessageAt,
    this.lastMessageSenderId,
    this.unreadCount = 0,
    this.isMuted = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      disappearingMessagesDuration:
          json['disappearing_messages_duration'] as String?,
    );
  }

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? disappearingMessagesDuration;
  final String? otherMemberUsername;
  final String? otherMemberId;
  final DateTime? otherMemberLastSeen;
  final String? lastMessageContent;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final int unreadCount;
  final bool isMuted;

  Conversation copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? disappearingMessagesDuration,
    String? otherMemberUsername,
    String? otherMemberId,
    DateTime? otherMemberLastSeen,
    String? lastMessageContent,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    int? unreadCount,
    bool? isMuted,
  }) {
    return Conversation(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      disappearingMessagesDuration:
          disappearingMessagesDuration ?? this.disappearingMessagesDuration,
      otherMemberUsername: otherMemberUsername ?? this.otherMemberUsername,
      otherMemberId: otherMemberId ?? this.otherMemberId,
      otherMemberLastSeen: otherMemberLastSeen ?? this.otherMemberLastSeen,
      lastMessageContent: lastMessageContent ?? this.lastMessageContent,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Conversation(id: $id, other: $otherMemberUsername)';
}

/// Represents a conversation member row.
class ConversationMember {
  const ConversationMember({
    required this.conversationId,
    required this.userId,
    required this.joinedAt,
    this.lastReadMessageId,
    this.isMuted = false,
    this.username,
  });

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      conversationId: json['conversation_id'] as String,
      userId: json['user_id'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      lastReadMessageId: json['last_read_message_id'] as String?,
      isMuted: json['is_muted'] as bool? ?? false,
    );
  }

  final String conversationId;
  final String userId;
  final DateTime joinedAt;
  final String? lastReadMessageId;
  final bool isMuted;
  final String? username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationMember &&
          conversationId == other.conversationId &&
          userId == other.userId;

  @override
  int get hashCode => Object.hash(conversationId, userId);
}
