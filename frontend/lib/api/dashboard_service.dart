import 'api_client.dart';

class DashboardStats {
  final int assets;
  final int downloads;
  final int aiJobs;
  final int scanJobs;

  const DashboardStats({
    required this.assets,
    required this.downloads,
    required this.aiJobs,
    required this.scanJobs,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      assets: (json['assets'] ?? 0) as int,
      downloads: (json['downloads'] ?? 0) as int,
      aiJobs: (json['ai_jobs'] ?? 0) as int,
      scanJobs: (json['scan_jobs'] ?? 0) as int,
    );
  }
}

class DashboardService {
  DashboardService(this._api);

  final ApiClient _api;

  Future<DashboardStats> me() async {
    final data = await _api.getJson('/dashboard/me', auth: true);
    return DashboardStats.fromJson(data);
  }
}
