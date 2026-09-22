/// Delivery / read status of a message.
enum MessageStatus { sending, sent, delivered, read, failed }

/// Type of a message.
enum MessageType {
  text,
  image,
  viewOnceImage,
  audio,
  document,
  system,
  deleted;

  static MessageType fromString(String value) {
    switch (value) {
      case 'image':
        return MessageType.image;
      case 'view_once_image':
        return MessageType.viewOnceImage;
      case 'audio':
        return MessageType.audio;
      case 'document':
        return MessageType.document;
      case 'system':
        return MessageType.system;
      case 'deleted':
        return MessageType.deleted;
      case 'text':
      default:
        return MessageType.text;
    }
  }

  String toDbString() {
    switch (this) {
      case MessageType.viewOnceImage:
        return 'view_once_image';
      case MessageType.document:
        return 'document';
      default:
        return name;
    }
  }
}

/// Immutable representation of a chat message.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
    this.content,
    this.messageType = MessageType.text,
    this.clientId,
    this.mediaUrl,
    this.mediaData,
    this.mediaMeta,
    this.deliveredAt,
    this.readAt,
    this.viewedAt,
    this.deletedAt,
    this.expiresAt,
    this.status = MessageStatus.sent,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final deliveredAtStr = json['delivered_at'] as String?;
    final readAtStr = json['read_at'] as String?;
    final viewedAtStr = json['viewed_at'] as String?;
    final deletedAtStr = json['deleted_at'] as String?;
    final expiresAtStr = json['expires_at'] as String?;

    final deliveredAt = deliveredAtStr != null
        ? DateTime.parse(deliveredAtStr)
        : null;
    final readAt = readAtStr != null ? DateTime.parse(readAtStr) : null;
    final viewedAt = viewedAtStr != null ? DateTime.parse(viewedAtStr) : null;

    MessageStatus resolvedStatus = MessageStatus.sent;
    if (readAt != null) {
      resolvedStatus = MessageStatus.read;
    } else if (deliveredAt != null) {
      resolvedStatus = MessageStatus.delivered;
    }

    final isDocMeta =
        (json['media_meta'] as Map<String, dynamic>?)?['is_document'] == true;
    final msgType = isDocMeta
        ? MessageType.document
        : MessageType.fromString(json['message_type'] as String? ?? 'text');

    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String?,
      messageType: msgType,
      clientId: json['client_id'] as String?,
      mediaUrl: json['media_url'] as String?,
      mediaData: json['media_data'] as String?,
      mediaMeta: json['media_meta'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      deliveredAt: deliveredAt,
      readAt: readAt,
      viewedAt: viewedAt,
      deletedAt: deletedAtStr != null ? DateTime.parse(deletedAtStr) : null,
      expiresAt: expiresAtStr != null ? DateTime.parse(expiresAtStr) : null,
      status: resolvedStatus,
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String? content;
  final MessageType messageType;
  final String? clientId;
  final String? mediaUrl;
  final String? mediaData;
  final Map<String, dynamic>? mediaMeta;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? viewedAt;
  final DateTime? deletedAt;
  final DateTime? expiresAt;
  final MessageStatus status;

  /// Helper to check if this message was sent by the given user.
  bool isMine(String currentUserId) => senderId == currentUserId;

  /// True if message is soft-deleted.
  bool get isDeleted => deletedAt != null || messageType == MessageType.deleted;

  /// True if message is a view-once image.
  bool get isViewOnce => messageType == MessageType.viewOnceImage;

  /// True if view-once media has already been viewed.
  bool get isViewOnceOpened => isViewOnce && viewedAt != null;

  /// True if message is a normal image.
  bool get isImage => messageType == MessageType.image;

  /// True if message is a voice note.
  bool get isAudio => messageType == MessageType.audio;

  /// True if message is a document file.
  bool get isDocument =>
      messageType == MessageType.document ||
      (mediaMeta?['is_document'] == true);

  /// Document metadata helpers.
  String? get documentFileName => mediaMeta?['file_name'] as String? ?? content;
  int? get documentFileSize => mediaMeta?['file_size'] as int?;
  String? get documentMimeType => mediaMeta?['mime_type'] as String?;

  /// Reply quote metadata.
  String? get replyToId => mediaMeta?['reply_to_id'] as String?;
  String? get replyToContent => mediaMeta?['reply_to_content'] as String?;
  String? get replyToSender => mediaMeta?['reply_to_sender'] as String?;
  bool get hasReply => replyToContent != null && replyToContent!.isNotEmpty;

  /// Display text, masking deleted messages.
  String get displayText {
    if (isDeleted) {
      return 'This message was deleted';
    }
    if (isViewOnce) {
      return isViewOnceOpened ? 'Photo (Opened)' : 'Photo (View once)';
    }
    if (isDocument) {
      return '📄 ${documentFileName ?? "Document"}';
    }
    if (isImage) {
      return content?.isNotEmpty == true ? content! : 'Photo';
    }
    if (isAudio) {
      return 'Voice message';
    }
    return content ?? '';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType.toDbString(),
      'client_id': clientId,
      'media_url': mediaUrl,
      'media_data': mediaData,
      'media_meta': mediaMeta,
      'created_at': createdAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'viewed_at': viewedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    MessageType? messageType,
    String? clientId,
    String? mediaUrl,
    String? mediaData,
    bool clearMediaData = false,
    Map<String, dynamic>? mediaMeta,
    DateTime? createdAt,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? viewedAt,
    DateTime? deletedAt,
    DateTime? expiresAt,
    MessageStatus? status,
  }) {
    final effectiveType = messageType ?? this.messageType;
    final effectiveViewedAt = viewedAt ?? this.viewedAt;

    final effectiveMediaData = clearMediaData
        ? null
        : (mediaData ?? this.mediaData);

    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      messageType: effectiveType,
      clientId: clientId ?? this.clientId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaData: effectiveMediaData,
      mediaMeta: mediaMeta ?? this.mediaMeta,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      viewedAt: effectiveViewedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          readAt == other.readAt &&
          viewedAt == other.viewedAt &&
          deliveredAt == other.deliveredAt &&
          deletedAt == other.deletedAt;

  @override
  int get hashCode =>
      Object.hash(id, status, readAt, viewedAt, deliveredAt, deletedAt);
}
