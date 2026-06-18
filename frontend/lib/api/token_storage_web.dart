// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

import 'token_pair.dart';
import 'token_storage.dart';

class TokenStorageImpl implements TokenStorage {
  static const String _kLocalKey = 'r2v_tokens';
  static const String _kSessionKey = 'r2v_tokens_session';

  TokenPair? _decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return TokenPair.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  String _encode(TokenPair tokens) => jsonEncode(tokens.toJson());

  @override
  Future<TokenPair?> load() async {
    // Prefer persistent tokens (localStorage). If none, fallback to sessionStorage.
    final local = html.window.localStorage[_kLocalKey];
    if (local != null && local.isNotEmpty) {
      final parsed = _decode(local);
      if (parsed != null) return parsed;
    }

    final session = html.window.sessionStorage[_kSessionKey];
    if (session != null && session.isNotEmpty) {
      final parsed = _decode(session);
      if (parsed != null) return parsed;
    }

    return null;
  }

  @override
  Future<void> save(TokenPair tokens, {required bool persist}) async {
    final raw = _encode(tokens);

    if (persist) {
      // Store persistently and clear session copy to avoid ambiguity.
      html.window.localStorage[_kLocalKey] = raw;
      html.window.sessionStorage.remove(_kSessionKey);
    } else {
      // Store for the current browser session only.
      html.window.sessionStorage[_kSessionKey] = raw;
      html.window.localStorage.remove(_kLocalKey);
    }
  }

  @override
  Future<void> clear() async {
    html.window.localStorage.remove(_kLocalKey);
    html.window.sessionStorage.remove(_kSessionKey);
  }

  @override
  Future<bool> isPersistent() async {
    final local = html.window.localStorage[_kLocalKey];
    return local != null && local.isNotEmpty;
  }

  @override
  Future<String?> getAccessToken() async => (await load())?.accessToken;

  @override
  Future<String?> getRefreshToken() async => (await load())?.refreshToken;
}
