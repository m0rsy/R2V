import 'api_client.dart';

class PasswordResetRequestResult {
  final String? devCode;

  const PasswordResetRequestResult({this.devCode});

  factory PasswordResetRequestResult.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequestResult(
      devCode: json['dev_code']?.toString(),
    );
  }
}

class PasswordResetService {
  PasswordResetService(this._api);

  final ApiClient _api;

  Future<PasswordResetRequestResult> requestReset(String email) async {
    final data = await _api.postJson('/auth/password/forgot',
        auth: false, body: {'email': email});
    return PasswordResetRequestResult.fromJson(data);
  }

  Future<String> verifyCode(String email, String code) async {
    final data = await _api.postJson('/auth/password/verify',
        auth: false, body: {'email': email, 'code': code});
    return data['reset_token']?.toString() ?? '';
  }

  Future<void> resetPassword(String resetToken, String newPassword) async {
    await _api.postJson('/auth/password/reset', auth: false, body: {
      'reset_token': resetToken,
      'new_password': newPassword,
    });
  }
}
