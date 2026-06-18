import 'dart:typed_data';

import 'api_client.dart';

String _s(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;
int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int? _iOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class ChatAttachment {
  final String id;
  final String? url;
  final String fileName;
  final String mimeType;
  final int fileSize;

  /// image | document | voice | model | other
  final String attachmentType;
  final int? durationSeconds;

  const ChatAttachment({
    required this.id,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.attachmentType,
    required this.durationSeconds,
  });

  bool get isImage => attachmentType == 'image';
  bool get isVoice => attachmentType == 'voice';

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        id: _s(json['id']),
        url: json['url']?.toString(),
        fileName: _s(json['file_name'], 'file'),
        mimeType: _s(json['mime_type'], 'application/octet-stream'),
        fileSize: _i(json['file_size']),
        attachmentType: _s(json['attachment_type'], 'other'),
        durationSeconds: _iOrNull(json['duration_seconds']),
      );
}

class ChatUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final String role;

  const ChatUser({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.role,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) => ChatUser(
        id: _s(json['id']),
        username: _s(json['username'], 'User'),
        avatarUrl: json['avatar_url']?.toString(),
        role: _s(json['role'], 'user'),
      );
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String body;

  /// text | attachment | voice | mixed
  final String messageType;
  final String createdAt;
  final String? editedAt;
  final bool isMine;
  final ChatUser sender;
  final List<ChatAttachment> attachments;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.body,
    required this.messageType,
    required this.createdAt,
    required this.editedAt,
    required this.isMine,
    required this.sender,
    required this.attachments,
  });

  bool get hasAttachments => attachments.isNotEmpty;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: _s(json['id']),
        conversationId: _s(json['conversation_id']),
        body: _s(json['body']),
        messageType: _s(json['message_type'], 'text'),
        createdAt: _s(json['created_at']),
        editedAt: json['edited_at']?.toString(),
        isMine: json['is_mine'] == true,
        sender: ChatUser.fromJson(
          (json['sender'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        attachments: (json['attachments'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ChatAttachment.fromJson)
            .toList(),
      );
}

class ChatConversation {
  final String id;
  final String? title;
  final bool isGroup;
  final List<ChatUser> participants;
  final ChatMessage? lastMessage;
  final String? lastMessageAt;
  final int unreadCount;
  final String updatedAt;

  const ChatConversation({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.updatedAt,
  });

  /// Best display partner for a 1:1 conversation, given the current user id.
  ChatUser? otherParticipant(String myId) {
    for (final p in participants) {
      if (p.id != myId) return p;
    }
    return participants.isNotEmpty ? participants.first : null;
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final lm = json['last_message'];
    return ChatConversation(
      id: _s(json['id']),
      title: json['title']?.toString(),
      isGroup: json['is_group'] == true,
      participants: (json['participants'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatUser.fromJson)
          .toList(),
      lastMessage: lm is Map
          ? ChatMessage.fromJson(lm.cast<String, dynamic>())
          : null,
      lastMessageAt: json['last_message_at']?.toString(),
      unreadCount: _i(json['unread_count']),
      updatedAt: _s(json['updated_at']),
    );
  }
}

class ConversationDetail {
  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final bool hasMore;

  const ConversationDetail({
    required this.conversation,
    required this.messages,
    required this.hasMore,
  });

  factory ConversationDetail.fromJson(Map<String, dynamic> json) =>
      ConversationDetail(
        conversation: ChatConversation.fromJson(
          (json['conversation'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        messages: (json['messages'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList(),
        hasMore: json['has_more'] == true,
      );
}

class ChatService {
  ChatService(this._api);

  final ApiClient _api;

  Future<List<ChatUser>> searchUsers({String search = ''}) async {
    final rows = await _api.getJsonList('/chat/users',
        auth: true, query: search.isEmpty ? null : {'search': search});
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ChatUser.fromJson)
        .toList();
  }

  Future<List<ChatConversation>> conversations() async {
    final rows = await _api.getJsonList('/chat/conversations', auth: true);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ChatConversation.fromJson)
        .toList();
  }

  Future<ChatConversation> startConversation(List<String> participantIds) async {
    final data = await _api.postJson('/chat/conversations',
        auth: true, body: {'participant_ids': participantIds});
    return ChatConversation.fromJson(data);
  }

  Future<ConversationDetail> messages(
    String conversationId, {
    int limit = 50,
    String? before,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null && before.isNotEmpty) query['before'] = before;
    final data = await _api.getJson(
      '/chat/conversations/$conversationId/messages',
      auth: true,
      query: query,
    );
    return ConversationDetail.fromJson(data);
  }

  Future<ConversationDetail> send(String conversationId, String text) async {
    final data = await _api.postJson(
      '/chat/conversations/$conversationId/messages',
      auth: true,
      body: {'text': text},
    );
    return ConversationDetail.fromJson(data);
  }

  /// Upload a file attachment (image / document / 3D model) to a conversation.
  Future<ConversationDetail> sendAttachment(
    String conversationId, {
    required Uint8List bytes,
    required String fileName,
    String? contentType,
    String? text,
    String kind = 'auto',
  }) async {
    final data = await _api.postMultipart(
      '/chat/conversations/$conversationId/attachments',
      fileBytes: bytes,
      fileName: fileName,
      contentType: contentType,
      fields: {
        'kind': kind,
        if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      },
    );
    return ConversationDetail.fromJson(data);
  }

  /// Upload a recorded voice note to a conversation.
  Future<ConversationDetail> sendVoiceNote(
    String conversationId, {
    required Uint8List bytes,
    required String fileName,
    String? contentType,
    int? durationSeconds,
  }) async {
    final data = await _api.postMultipart(
      '/chat/conversations/$conversationId/voice-note',
      fileBytes: bytes,
      fileName: fileName,
      contentType: contentType,
      fields: {
        'kind': 'voice',
        if (durationSeconds != null) 'duration_seconds': '$durationSeconds',
      },
    );
    return ConversationDetail.fromJson(data);
  }
}
