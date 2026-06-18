import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'api_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

class ApiClient {
  static const bool _verbose =
      bool.fromEnvironment('R2V_API_VERBOSE', defaultValue: false);

  ApiClient({
    http.Client? httpClient,
    TokenStore? tokenStore,
    Duration timeout = const Duration(seconds: 20),
  })  : _http = httpClient ?? http.Client(),
        _tokens = tokenStore ?? DefaultTokenStore(),
        _timeout = timeout;

  final http.Client _http;
  final TokenStore _tokens;
  final Duration _timeout;

  String get _base => ApiConfig.baseUrl;

  Future<Map<String, String>> _headers({required bool auth}) async {
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (auth) {
      final token = await _tokens.getAccessToken();
      if (token != null && token.isNotEmpty) {
        h['Authorization'] = 'Bearer $token';
      }
    }
    return h;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse('$_base$p');
    return query == null ? u : u.replace(queryParameters: query);
  }

  void _log(String message) {
    if (!_verbose) return;
    // ignore: avoid_print
    print('[R2V API] $message');
  }

  Future<http.Response> _sendWithRefresh(
    Future<http.Response> Function() request, {
    required bool auth,
  }) async {
    http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Request timeout');
    }

    if (!auth || res.statusCode != 401) return res;

    // attempt refresh once
    final refreshed = await _refreshToken();
    if (!refreshed) return res;

    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Request timeout');
    }
  }

  Future<bool> _refreshToken() async {
    final rt = await _tokens.getRefreshToken();
    if (rt == null || rt.isEmpty) return false;

    final uri = _uri('/auth/refresh');
    final res = await _http
        .post(uri, headers: await _headers(auth: false), body: jsonEncode({'refresh_token': rt}))
        .timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) return false;

    final data = _decodeJson(res);
    final access = (data['access_token'] ?? '').toString();
    final refresh = (data['refresh_token'] ?? '').toString();
    if (access.isEmpty || refresh.isEmpty) return false;

    await _tokens.saveTokens(accessToken: access, refreshToken: refresh);
    return true;
  }

  Map<String, dynamic> _decodeJson(http.Response res) {
    try {
      final body = res.body.trim();
      if (body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'data': decoded};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  List<dynamic> _decodeJsonList(http.Response res) {
    try {
      final body = res.body.trim();
      if (body.isEmpty) return <dynamic>[];
      final decoded = jsonDecode(body);
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        return decoded['data'] as List;
      }
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  String _errorMessage(http.Response res) {
    final j = _decodeJson(res);
    final msg = j['detail'] ?? j['message'] ?? j['error'];
    if (msg is String && msg.trim().isNotEmpty) return msg;
    return 'Request failed';
  }

  Future<Map<String, dynamic>> getJson(String path, {bool auth = false, Map<String, String>? query}) async {
    final uri = _uri(path, query);
    _log('GET $uri');
    final res = await _sendWithRefresh(
      () async => _http.get(uri, headers: await _headers(auth: auth)),
      auth: auth,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('GET $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('GET $uri -> ${res.statusCode}');
    return _decodeJson(res);
  }

  Future<List<dynamic>> getJsonList(String path,
      {bool auth = false, Map<String, String>? query}) async {
    final uri = _uri(path, query);
    _log('GET $uri');
    final res = await _sendWithRefresh(
      () async => _http.get(uri, headers: await _headers(auth: auth)),
      auth: auth,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('GET $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('GET $uri -> ${res.statusCode}');
    return _decodeJsonList(res);
  }

  Future<Map<String, dynamic>> postJson(String path, {bool auth = false, Map<String, dynamic>? body}) async {
    final uri = _uri(path);
    _log('POST $uri');
    final res = await _sendWithRefresh(
      () async => _http.post(uri, headers: await _headers(auth: auth), body: jsonEncode(body ?? {})),
      auth: auth,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('POST $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('POST $uri -> ${res.statusCode}');
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> putJson(String path, {bool auth = false, Map<String, dynamic>? body}) async {
    final uri = _uri(path);
    _log('PUT $uri');
    final res = await _sendWithRefresh(
      () async => _http.put(uri, headers: await _headers(auth: auth), body: jsonEncode(body ?? {})),
      auth: auth,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('PUT $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('PUT $uri -> ${res.statusCode}');
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> patchJson(String path, {bool auth = false, Map<String, dynamic>? body}) async {
    final uri = _uri(path);
    _log('PATCH $uri');
    final res = await _sendWithRefresh(
      () async => _http.patch(uri, headers: await _headers(auth: auth), body: jsonEncode(body ?? {})),
      auth: auth,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('PATCH $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('PATCH $uri -> ${res.statusCode}');
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> deleteJson(String path, {bool auth = false, Map<String, dynamic>? body}) async {
    final uri = _uri(path);
    _log('DELETE $uri');
    final req = http.Request('DELETE', uri);
    req.headers.addAll(await _headers(auth: auth));
    if (body != null) req.body = jsonEncode(body);

    final res = await _sendWithRefresh(
      () async => http.Response.fromStream(await _http.send(req)),
      auth: auth,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('DELETE $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('DELETE $uri -> ${res.statusCode}');
    return _decodeJson(res);
  }

  /// Multipart upload of a single file plus optional form fields.
  ///
  /// Works on web and native because the file is sent as in-memory bytes
  /// (no dart:io path required). Retries once on 401 after a token refresh.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Uint8List fileBytes,
    required String fileName,
    String fileField = 'file',
    String? contentType,
    Map<String, String>? fields,
    bool auth = true,
  }) async {
    final uri = _uri(path);
    _log('POST(multipart) $uri');

    Future<http.Response> send() async {
      final req = http.MultipartRequest('POST', uri);
      if (auth) {
        final token = await _tokens.getAccessToken();
        if (token != null && token.isNotEmpty) {
          req.headers['Authorization'] = 'Bearer $token';
        }
      }
      req.headers['Accept'] = 'application/json';
      if (fields != null) req.fields.addAll(fields);
      req.files.add(
        http.MultipartFile.fromBytes(
          fileField,
          fileBytes,
          filename: fileName,
          contentType: contentType != null ? MediaType.parse(contentType) : null,
        ),
      );
      return http.Response.fromStream(await _http.send(req)).timeout(_timeout);
    }

    final res = await _sendWithRefresh(send, auth: auth);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('POST(multipart) $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('POST(multipart) $uri -> ${res.statusCode}');
    return _decodeJson(res);
  }

  /// Multipart POST with form fields and an *optional* file. Use when an
  /// endpoint accepts both message-only and file-bearing submissions
  /// (e.g. freelance deliveries). Retries once on 401 after a token refresh.
  Future<Map<String, dynamic>> postMultipartForm(
    String path, {
    Map<String, String>? fields,
    Uint8List? fileBytes,
    String? fileName,
    String fileField = 'file',
    String? contentType,
    bool auth = true,
  }) async {
    final uri = _uri(path);
    _log('POST(multipart-form) $uri');

    Future<http.Response> send() async {
      final req = http.MultipartRequest('POST', uri);
      if (auth) {
        final token = await _tokens.getAccessToken();
        if (token != null && token.isNotEmpty) {
          req.headers['Authorization'] = 'Bearer $token';
        }
      }
      req.headers['Accept'] = 'application/json';
      if (fields != null) req.fields.addAll(fields);
      if (fileBytes != null) {
        req.files.add(
          http.MultipartFile.fromBytes(
            fileField,
            fileBytes,
            filename: fileName ?? 'file',
            contentType:
                contentType != null ? MediaType.parse(contentType) : null,
          ),
        );
      }
      return http.Response.fromStream(await _http.send(req)).timeout(_timeout);
    }

    final res = await _sendWithRefresh(send, auth: auth);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('POST(multipart-form) $uri -> ${res.statusCode}');
      throw ApiException(_errorMessage(res), statusCode: res.statusCode);
    }
    _log('POST(multipart-form) $uri -> ${res.statusCode}');
    return _decodeJson(res);
  }

  TokenStore get tokenStore => _tokens;
}
