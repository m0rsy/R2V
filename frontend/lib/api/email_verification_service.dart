import 'api_client.dart';

class EmailVerificationRequestResult {
  final String? devCode;

  const EmailVerificationRequestResult({this.devCode});

  factory EmailVerificationRequestResult.fromJson(Map<String, dynamic> json) {
    return EmailVerificationRequestResult(
      devCode: json['dev_code']?.toString(),
    );
  }
}

class EmailVerificationService {
  EmailVerificationService(this._api);

  final ApiClient _api;

  Future<EmailVerificationRequestResult> requestCode(String email) async {
    final data = await _api.postJson('/auth/verify/request',
        auth: false, body: {'email': email});
    return EmailVerificationRequestResult.fromJson(data);
  }

  /// Confirms the emailed code. On success the backend marks the account
  /// verified and returns app tokens, which we persist so the user enters the
  /// app directly after OTP.
  Future<void> verifyCode(String email, String code, {bool persist = true}) async {
    final data = await _api.postJson('/auth/verify/confirm',
        auth: false, body: {'email': email, 'code': code});

    await _api.tokenStore.saveTokens(
      accessToken: (data['access_token'] ?? '').toString(),
      refreshToken: (data['refresh_token'] ?? '').toString(),
      persist: persist,
    );
  }
}
