import 'api_client.dart';

class SocialProfile {
  final String userId;
  final String username;
  final String? bio;
  final String? avatarUrl;
  final int posts;
  final int followers;
  final int following;
  final bool isFollowing;
  final bool isFollowedBy;
  final bool isMutual;
  final bool isSelf;

  const SocialProfile({
    required this.userId,
    required this.username,
    required this.bio,
    required this.avatarUrl,
    required this.posts,
    required this.followers,
    required this.following,
    required this.isFollowing,
    required this.isFollowedBy,
    required this.isMutual,
    required this.isSelf,
  });

  factory SocialProfile.fromJson(Map<String, dynamic> json) {
    return SocialProfile(
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      bio: json['bio']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      posts: (json['posts'] ?? 0) as int,
      followers: (json['followers'] ?? 0) as int,
      following: (json['following'] ?? 0) as int,
      isFollowing: json['is_following'] == true,
      isFollowedBy: json['is_followed_by'] == true,
      isMutual: json['is_mutual'] == true,
      isSelf: json['is_self'] == true,
    );
  }
}

class SocialUser {
  final String userId;
  final String username;
  final String? avatarUrl;

  const SocialUser({required this.userId, required this.username, required this.avatarUrl});

  factory SocialUser.fromJson(Map<String, dynamic> json) {
    return SocialUser(
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
    );
  }
}

class SocialService {
  SocialService(this._api);

  final ApiClient _api;

  Future<SocialProfile> getProfile(String userId) async {
    final data = await _api.getJson('/social/profile/$userId', auth: true);
    return SocialProfile.fromJson(data);
  }

  Future<void> follow(String userId) async {
    await _api.postJson('/social/follow/$userId', auth: true);
  }

  Future<void> unfollow(String userId) async {
    await _api.deleteJson('/social/follow/$userId', auth: true);
  }

  Future<List<SocialUser>> getFollowers(String userId) async {
    final data = await _api.getJsonList('/social/followers/$userId', auth: true);
    return data.map((entry) => SocialUser.fromJson(entry as Map<String, dynamic>)).toList();
  }

  Future<List<SocialUser>> getFollowing(String userId) async {
    final data = await _api.getJsonList('/social/following/$userId', auth: true);
    return data.map((entry) => SocialUser.fromJson(entry as Map<String, dynamic>)).toList();
  }
}
