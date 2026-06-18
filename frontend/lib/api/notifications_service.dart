import 'api_client.dart';

/// A single notification row from `GET /notifications/`.
///
/// The backend stores a free-form `payload` (JSONB) plus a `type`, so we read
/// the title/message defensively out of the payload and never fabricate copy —
/// if the payload has no title/message we fall back to a humanised type.
class R2VNotification {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime? createdAt;

  const R2VNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.isRead,
    required this.createdAt,
  });

  factory R2VNotification.fromJson(Map<String, dynamic> j) {
    final p = j['payload'];
    return R2VNotification(
      id: j['id']?.toString() ?? '',
      type: j['type']?.toString() ?? '',
      payload: p is Map ? Map<String, dynamic>.from(p) : const {},
      isRead: j['is_read'] == true,
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
    );
  }

  /// Title from the payload, or a humanised version of [type] (e.g.
  /// "order_completed" -> "Order completed").
  String get title {
    final t = payload['title'];
    if (t is String && t.trim().isNotEmpty) return t.trim();
    if (type.isEmpty) return 'Notification';
    final words = type.replaceAll('_', ' ').replaceAll('.', ' ').trim();
    if (words.isEmpty) return 'Notification';
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Optional body line, if the payload carries one.
  String? get message {
    for (final k in const ['message', 'body', 'text', 'description']) {
      final v = payload[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}

/// Wraps the backend notifications API (`/notifications`).
///
/// Endpoints that exist today: list + mark-one-read. There is no unread-count
/// or mark-all endpoint, so the UI derives the unread count from the list and
/// implements "mark all read" by marking each unread item via [markRead].
class NotificationsService {
  NotificationsService(this._api);

  final ApiClient _api;

  Future<List<R2VNotification>> list({int limit = 50, int offset = 0}) async {
    final raw = await _api.getJsonList(
      '/notifications/',
      auth: true,
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return raw
        .whereType<Map<String, dynamic>>()
        .map(R2VNotification.fromJson)
        .toList();
  }

  Future<void> markRead(String id) async {
    await _api.postJson('/notifications/$id/read', auth: true);
  }
}
