import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';

class ScanJob {
  final String id;
  final String status;
  final int progress;

  const ScanJob({
    required this.id,
    required this.status,
    required this.progress,
  });

  factory ScanJob.fromJson(Map<String, dynamic> json) {
    return ScanJob(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      progress: (json['progress'] ?? 0) as int,
    );
  }
}

class ScanUpload {
  final String filename;
  final Uint8List bytes;
  final String contentType;

  const ScanUpload({
    required this.filename,
    required this.bytes,
    required this.contentType,
  });
}

class ScanJobsService {
  ScanJobsService(this._api);

  final ApiClient _api;

  Future<ScanJob> createJob({String kind = 'photos'}) async {
    final data = await _api.postJson('/scan/jobs', auth: true, body: {'kind': kind});
    return ScanJob.fromJson(data);
  }

  Future<List<ScanJob>> listJobs({int limit = 20, int offset = 0}) async {
    final list = await _api.getJsonList('/scan/jobs',
        auth: true, query: {'limit': '$limit', 'offset': '$offset'});
    return list
        .whereType<Map<String, dynamic>>()
        .map(ScanJob.fromJson)
        .toList();
  }

  Future<String> presignUpload({
    required String jobId,
    required String filename,
    required String contentType,
  }) async {
    final data = await _api.postJson(
      '/scan/jobs/$jobId/presign',
      auth: true,
      body: {
        'filename': filename,
        'content_type': contentType,
      },
    );
    return data['url']?.toString() ?? '';
  }

  Future<void> uploadToPresignedUrl(String url, Uint8List bytes, String contentType) async {
    final res = await http.put(
      Uri.parse(url),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Upload failed (${res.statusCode})');
    }
  }

  Future<ScanJob> startJob(String jobId) async {
    final data = await _api.postJson('/scan/jobs/$jobId/start', auth: true);
    return ScanJob.fromJson(data);
  }
}
