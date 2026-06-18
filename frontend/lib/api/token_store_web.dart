// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'token_store_impl.dart';

class TokenStoreImpl implements TokenStore {
  static const _kAccess = 'r2v_access_token';
  static const _kRefresh = 'r2v_refresh_token';
  static const _kAccessSession = 'r2v_access_token_session';
  static const _kRefreshSession = 'r2v_refresh_token_session';

  @override
  Future<String?> getAccessToken() async =>
      html.window.localStorage[_kAccess] ?? html.window.sessionStorage[_kAccessSession];

  @override
  Future<String?> getRefreshToken() async =>
      html.window.localStorage[_kRefresh] ?? html.window.sessionStorage[_kRefreshSession];

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    bool persist = true,
  }) async {
    if (persist) {
      html.window.localStorage[_kAccess] = accessToken;
      html.window.localStorage[_kRefresh] = refreshToken;
      html.window.sessionStorage.remove(_kAccessSession);
      html.window.sessionStorage.remove(_kRefreshSession);
      return;
    }

    html.window.sessionStorage[_kAccessSession] = accessToken;
    html.window.sessionStorage[_kRefreshSession] = refreshToken;
    html.window.localStorage.remove(_kAccess);
    html.window.localStorage.remove(_kRefresh);
  }

  @override
  Future<void> clear() async {
    html.window.localStorage.remove(_kAccess);
    html.window.localStorage.remove(_kRefresh);
    html.window.sessionStorage.remove(_kAccessSession);
    html.window.sessionStorage.remove(_kRefreshSession);
  }
}
