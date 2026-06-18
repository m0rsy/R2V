import 'api_client.dart';

/// Result of a signup. When verification is required the account is not logged
/// in (the UI routes to the verify screen). When the backend has verification
/// disabled (REQUIRE_EMAIL_VERIFICATION=false) it returns tokens and the user
/// enters the app directly — [AuthService.signup] persists those tokens and
/// reports it via [requiresVerification] == false.
class SignupResult {
  final String email;
  final bool requiresVerification;
  final String? devCode;

  const SignupResult({
    required this.email,
    this.requiresVerification = true,
    this.devCode,
  });

  factory SignupResult.fromJson(Map<String, dynamic> json, String fallbackEmail) {
    return SignupResult(
      email: (json['email'] ?? fallbackEmail).toString(),
      requiresVerification: json['requires_verification'] != false,
      devCode: json['dev_code']?.toString(),
    );
  }
}

class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  Future<SignupResult> signup({
    required String email,
    required String password,
    required String username,
    bool persist = true,
  }) async {
    final data = await _api.postJson('/auth/signup', auth: false, body: {
      'email': email,
      'password': password,
      'username': username,
    });

    final result = SignupResult.fromJson(data, email);

    // Normal path (verification required): the backend does NOT issue app tokens
    // until the email is verified via /auth/verify/confirm, so nothing to save.
    // Bypass path (REQUIRE_EMAIL_VERIFICATION=false): the backend returns tokens
    // so the user can enter the app immediately — persist them here.
    if (!result.requiresVerification) {
      final access = (data['access_token'] ?? '').toString();
      final refresh = (data['refresh_token'] ?? '').toString();
      if (access.isNotEmpty && refresh.isNotEmpty) {
        await _api.tokenStore.saveTokens(
          accessToken: access,
          refreshToken: refresh,
          persist: persist,
        );
      }
    }

    return result;
  }

  Future<void> login({
    required String email,
    required String password,
    bool persist = true,
  }) async {
    final data = await _api.postJson('/auth/login', auth: false, body: {
      'email': email,
      'password': password,
    });

    await _api.tokenStore.saveTokens(
      accessToken: (data['access_token'] ?? '').toString(),
      refreshToken: (data['refresh_token'] ?? '').toString(),
      persist: persist,
    );
  }

  Future<void> logout() async {
    // Backend supports /auth/logout but it needs refresh_token. We'll call it if present.
    final rt = await _api.tokenStore.getRefreshToken();
    if (rt != null && rt.isNotEmpty) {
      try {
        await _api.postJson('/auth/logout', auth: false, body: {'refresh_token': rt});
      } catch (_) {
        // ignore network/logout errors; we'll still clear locally
      }
    }
    await _api.tokenStore.clear();
  }

  Future<Map<String, dynamic>> me() async {
    return _api.getJson('/me', auth: true);
  }

  Future<void> changePassword(String newPassword) async {
    await _api.postJson('/auth/password/change', auth: true, body: {
      'new_password': newPassword,
    });
  }
}
