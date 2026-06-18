import 'dart:convert';

import 'api_client.dart';

class ProfileData {
  final String id;
  final String email;
  final String role;
  final String username;
  final String? bio;
  final String? avatarUrl;
  final bool emailVerified;
  final Map<String, dynamic> meta;

  const ProfileData({
    required this.id,
    required this.email,
    required this.role,
    required this.username,
    this.bio,
    this.avatarUrl,
    this.emailVerified = false,
    required this.meta,
  });

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    final rawLinks = json['links']?.toString();
    Map<String, dynamic> meta = {};
    if (rawLinks != null && rawLinks.isNotEmpty) {
      try {
        meta = jsonDecode(rawLinks) as Map<String, dynamic>;
      } catch (_) {
        meta = {};
      }
    }

    return ProfileData(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      bio: json['bio']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      emailVerified: json['email_verified'] == true,
      meta: meta,
    );
  }
}

class ProfileService {
  ProfileService(this._api);

  final ApiClient _api;

  Future<ProfileData> me() async {
    final data = await _api.getJson('/me', auth: true);
    return ProfileData.fromJson(data);
  }

  Future<ProfileData> update({
    String? username,
    String? bio,
    String? avatarUrl,
    Map<String, dynamic>? meta,
  }) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;
    if (meta != null) body['links'] = jsonEncode(meta);

    final data = await _api.patchJson('/me', auth: true, body: body);
    return ProfileData.fromJson(data);
  }

  Future<void> deleteAccount() async {
    await _api.deleteJson('/me', auth: true);
  }
}
