import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';
import 'token_store.dart';
import '../utils/photogrammetry_download.dart';

class PhotogrammetryUploadFile {
  final String filename;
  final Uint8List bytes;
  final String contentType;

  const PhotogrammetryUploadFile({
    required this.filename,
    required this.bytes,
    required this.contentType,
  });
}

class PhotogrammetryJobCreated {
  final String jobId;
  final String status;
  final int progress;

  const PhotogrammetryJobCreated({
    required this.jobId,
    required this.status,
    required this.progress,
  });

  factory PhotogrammetryJobCreated.fromJson(Map<String, dynamic> json) {
    return PhotogrammetryJobCreated(
      jobId: json['job_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      progress: (json['progress'] ?? 0) as int,
    );
  }
}

class PhotogrammetryJobStatus {
  final String jobId;
  final String status;
  final int progress;
  final String? error;
  final String createdAt;
  final String updatedAt;

  const PhotogrammetryJobStatus({
    required this.jobId,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    this.error,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  factory PhotogrammetryJobStatus.fromJson(Map<String, dynamic> json) {
    return PhotogrammetryJobStatus(
      jobId: json['job_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      progress: (json['progress'] ?? 0) as int,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      error: json['error']?.toString(),
    );
  }
}

class PhotogrammetryOutputFile {
  final String filename;
  final int fileSize;
  final String downloadUrl;

  const PhotogrammetryOutputFile({
    required this.filename,
    required this.fileSize,
    required this.downloadUrl,
  });

  bool get isGlb => filename.toLowerCase().endsWith('.glb');

  factory PhotogrammetryOutputFile.fromJson(Map<String, dynamic> json) {
    return PhotogrammetryOutputFile(
      filename: json['filename']?.toString() ?? '',
      fileSize: (json['file_size'] ?? 0) as int,
      downloadUrl: json['download_url']?.toString() ?? '',
    );
  }
}

class PhotogrammetryJobOutput {
  final String jobId;
  final String status;
  final List<PhotogrammetryOutputFile> files;

  const PhotogrammetryJobOutput({
    required this.jobId,
    required this.status,
    required this.files,
  });

  factory PhotogrammetryJobOutput.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final files = rawFiles is List
        ? rawFiles
            .whereType<Map<String, dynamic>>()
            .map(PhotogrammetryOutputFile.fromJson)
            .toList()
        : <PhotogrammetryOutputFile>[];
    return PhotogrammetryJobOutput(
      jobId: json['job_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      files: files,
    );
  }
}

class PhotogrammetryApiService {
  PhotogrammetryApiService({http.Client? client, TokenStore? tokenStore})
      : _client = client ?? http.Client(),
        _tokens = tokenStore ?? DefaultTokenStore();

  final http.Client _client;
  final TokenStore _tokens;

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ApiConfig.baseUrl}$normalized');
  }

  // Photogrammetry jobs are user-owned; the JSON endpoints require the bearer
  // access token. Download URLs already embed a short-lived signed token, so
  // file downloads / the GLB preview do not need a header.
  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokens.getAccessToken();
    if (token != null && token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
    return <String, String>{};
  }

  String buildAbsoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return _uri(path).toString();
  }

  Future<PhotogrammetryJobCreated> createJob(List<PhotogrammetryUploadFile> files) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/photogrammetry/jobs'),
    );
    request.headers.addAll(await _authHeaders());
    for (final file in files) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          file.bytes,
          filename: file.filename,
        ),
      );
    }
    final response = await http.Response.fromStream(await _client.send(request));
    _throwIfNeeded(response);
    return PhotogrammetryJobCreated.fromJson(_decodeMap(response));
  }

  Future<PhotogrammetryJobStatus> getJobStatus(String jobId) async {
    final response = await _client.get(
      _uri('/api/photogrammetry/jobs/$jobId/status'),
      headers: await _authHeaders(),
    );
    _throwIfNeeded(response);
    return PhotogrammetryJobStatus.fromJson(_decodeMap(response));
  }

  Future<List<PhotogrammetryJobStatus>> listJobs({int limit = 20}) async {
    final response = await _client.get(
      _uri('/api/photogrammetry/jobs?limit=$limit'),
      headers: await _authHeaders(),
    );
    _throwIfNeeded(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return <PhotogrammetryJobStatus>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PhotogrammetryJobStatus.fromJson)
        .toList();
  }

  Future<PhotogrammetryJobOutput> getJobOutput(String jobId) async {
    final response = await _client.get(
      _uri('/api/photogrammetry/jobs/$jobId/output'),
      headers: await _authHeaders(),
    );
    _throwIfNeeded(response);
    return PhotogrammetryJobOutput.fromJson(_decodeMap(response));
  }

  Future<String> downloadOutputFile(PhotogrammetryOutputFile file) {
    return savePhotogrammetryDownload(
      url: buildAbsoluteUrl(file.downloadUrl),
      filename: file.filename.split('/').last,
      client: _client,
    );
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  void _throwIfNeeded(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final json = _decodeMap(response);
    final message = json['detail']?.toString() ??
        json['message']?.toString() ??
        'Request failed (${response.statusCode})';
    throw ApiException(message, statusCode: response.statusCode);
  }
}
