import 'api_client.dart';

String _s(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;
int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// A report row as returned to admins.
class ReportItem {
  final String id;
  final String reporterId;
  final String? reporterUsername;
  final String targetType;
  final String targetId;
  final String reason;
  final String? description;
  final String status;
  final String? adminNote;
  final String createdAt;

  const ReportItem({
    required this.id,
    required this.reporterId,
    required this.reporterUsername,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.description,
    required this.status,
    required this.adminNote,
    required this.createdAt,
  });

  factory ReportItem.fromJson(Map<String, dynamic> json) => ReportItem(
        id: _s(json['id']),
        reporterId: _s(json['reporter_id']),
        reporterUsername: json['reporter_username']?.toString(),
        targetType: _s(json['target_type']),
        targetId: _s(json['target_id']),
        reason: _s(json['reason']),
        description: json['description']?.toString(),
        status: _s(json['status'], 'pending'),
        adminNote: json['admin_note']?.toString(),
        createdAt: _s(json['created_at']),
      );
}

class AdminReports {
  final int total;
  final int pending;
  final int resolved;
  final int rejected;
  final List<ReportItem> reports;

  const AdminReports({
    required this.total,
    required this.pending,
    required this.resolved,
    required this.rejected,
    required this.reports,
  });

  factory AdminReports.fromJson(Map<String, dynamic> json) => AdminReports(
        total: _i(json['total']),
        pending: _i(json['pending']),
        resolved: _i(json['resolved']),
        rejected: _i(json['rejected']),
        reports: (json['reports'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ReportItem.fromJson)
            .toList(),
      );
}

class ReportService {
  ReportService(this._api);

  final ApiClient _api;

  /// Submit a report about an asset, model, freelancer, user, order, etc.
  Future<void> submit({
    required String targetType,
    required String targetId,
    required String reason,
    String? description,
  }) async {
    await _api.postJson('/reports', auth: true, body: {
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'description': description,
    });
  }

  // ----- Admin -----

  Future<AdminReports> adminReports({String? status}) async {
    final query = (status != null && status.isNotEmpty && status != 'all')
        ? {'status': status}
        : null;
    final data = await _api.getJson('/admin/reports', auth: true, query: query);
    return AdminReports.fromJson(data);
  }

  Future<void> resolve(String reportId, {String? note}) async {
    await _api.postJson('/admin/reports/$reportId/resolve',
        auth: true, body: {'admin_note': note});
  }

  Future<void> reject(String reportId, {String? note}) async {
    await _api.postJson('/admin/reports/$reportId/reject',
        auth: true, body: {'admin_note': note});
  }
}
