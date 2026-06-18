import 'api_client.dart';

/// Persisted AI-assistant chat history (backed by /ai/chats on the API).
/// Distinct from peer-to-peer DMs — this is the AI generation chat shown on the
/// AI page, scoped to the logged-in user so it survives logout/login + reloads.

class AiConversationSummary {
  final String id;
  final String? title;
  final String? lastJobId;
  final String createdAt;
  final String updatedAt;

  const AiConversationSummary({
    required this.id,
    required this.title,
    required this.lastJobId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiConversationSummary.fromJson(Map<String, dynamic> json) {
    return AiConversationSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString(),
      lastJobId: json['last_job_id']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

class AiChatMessageDto {
  final String id;
  final String role; // "user" | "assistant"
  final String? text;
  final String? modelUrl;
  final String? jobId;
  final Map<String, dynamic> meta;
  final String createdAt;

  const AiChatMessageDto({
    required this.id,
    required this.role,
    required this.text,
    required this.modelUrl,
    required this.jobId,
    required this.meta,
    required this.createdAt,
  });

  factory AiChatMessageDto.fromJson(Map<String, dynamic> json) {
    return AiChatMessageDto(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      text: json['text']?.toString(),
      modelUrl: json['model_url']?.toString(),
      jobId: json['job_id']?.toString(),
      meta: (json['meta'] as Map<String, dynamic>? ?? const {}),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

class AiChatService {
  AiChatService(this._api);

  final ApiClient _api;

  Future<List<AiConversationSummary>> listChats({int limit = 50, int offset = 0}) async {
    final list = await _api.getJsonList(
      '/ai/chats',
      auth: true,
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(AiConversationSummary.fromJson)
        .toList();
  }

  Future<AiConversationSummary> createChat({String? title}) async {
    final data = await _api.postJson(
      '/ai/chats',
      auth: true,
      body: {if (title != null && title.isNotEmpty) 'title': title},
    );
    return AiConversationSummary.fromJson(data);
  }

  Future<List<AiChatMessageDto>> getMessages(String chatId) async {
    final list = await _api.getJsonList('/ai/chats/$chatId/messages', auth: true);
    return list
        .whereType<Map<String, dynamic>>()
        .map(AiChatMessageDto.fromJson)
        .toList();
  }

  Future<AiChatMessageDto> addMessage(
    String chatId, {
    required String role,
    String? text,
    String? modelUrl,
    String? jobId,
    Map<String, dynamic> meta = const {},
  }) async {
    final data = await _api.postJson(
      '/ai/chats/$chatId/messages',
      auth: true,
      body: {
        'role': role,
        if (text != null) 'text': text,
        if (modelUrl != null) 'model_url': modelUrl,
        if (jobId != null) 'job_id': jobId,
        'meta': meta,
      },
    );
    return AiChatMessageDto.fromJson(data);
  }

  Future<AiConversationSummary> updateChat(
    String chatId, {
    String? title,
    String? lastJobId,
  }) async {
    final data = await _api.patchJson(
      '/ai/chats/$chatId',
      auth: true,
      body: {
        if (title != null) 'title': title,
        if (lastJobId != null) 'last_job_id': lastJobId,
      },
    );
    return AiConversationSummary.fromJson(data);
  }

  Future<void> deleteChat(String chatId) async {
    await _api.deleteJson('/ai/chats/$chatId', auth: true);
  }
}
