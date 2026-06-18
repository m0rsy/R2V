import 'api_client.dart';
import 'freelance_service.dart';

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _asString(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;

// ---------------------------------------------------------------------------
// System overview
// ---------------------------------------------------------------------------

class AdminRecentAsset {
  final String id;
  final String title;
  final String creatorId;
  final String visibility;
  final bool isPaid;
  final int price;
  final String createdAt;

  const AdminRecentAsset({
    required this.id,
    required this.title,
    required this.creatorId,
    required this.visibility,
    required this.isPaid,
    required this.price,
    required this.createdAt,
  });

  factory AdminRecentAsset.fromJson(Map<String, dynamic> json) {
    return AdminRecentAsset(
      id: _asString(json['id']),
      title: _asString(json['title']),
      creatorId: _asString(json['creator_id']),
      visibility: _asString(json['visibility'], 'draft'),
      isPaid: json['is_paid'] == true,
      price: _asInt(json['price']),
      createdAt: _asString(json['created_at']),
    );
  }
}

class AdminSummary {
  final int users;
  final int activeUsers;
  final int bannedUsers;
  final int freelancers;
  final int pendingApplications;
  final int approvedApplications;
  final int rejectedApplications;
  final int assets;
  final int publishedAssets;
  final int draftAssets;
  final int downloads;
  final int purchases;
  final int aiJobs;
  final int failedAiJobs;
  final int scanJobs;
  final List<AdminRecentAsset> recentAssets;

  const AdminSummary({
    required this.users,
    required this.activeUsers,
    required this.bannedUsers,
    required this.freelancers,
    required this.pendingApplications,
    required this.approvedApplications,
    required this.rejectedApplications,
    required this.assets,
    required this.publishedAssets,
    required this.draftAssets,
    required this.downloads,
    required this.purchases,
    required this.aiJobs,
    required this.failedAiJobs,
    required this.scanJobs,
    required this.recentAssets,
  });

  factory AdminSummary.fromJson(Map<String, dynamic> json) {
    return AdminSummary(
      users: _asInt(json['users']),
      activeUsers: _asInt(json['active_users']),
      bannedUsers: _asInt(json['banned_users']),
      freelancers: _asInt(json['freelancers']),
      pendingApplications: _asInt(json['pending_applications']),
      approvedApplications: _asInt(json['approved_applications']),
      rejectedApplications: _asInt(json['rejected_applications']),
      assets: _asInt(json['assets']),
      publishedAssets: _asInt(json['published_assets']),
      draftAssets: _asInt(json['draft_assets']),
      downloads: _asInt(json['downloads']),
      purchases: _asInt(json['purchases']),
      aiJobs: _asInt(json['ai_jobs']),
      failedAiJobs: _asInt(json['failed_ai_jobs']),
      scanJobs: _asInt(json['scan_jobs']),
      recentAssets: (json['recent_assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminRecentAsset.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Directory / users
// ---------------------------------------------------------------------------

class AdminUser {
  final String id;
  final String email;
  final String? username;
  final String role;
  final bool isActive;
  final String createdAt;

  const AdminUser({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: _asString(json['id']),
      email: _asString(json['email']),
      username: json['username']?.toString(),
      role: _asString(json['role'], 'user'),
      isActive: json['is_active'] != false,
      createdAt: _asString(json['created_at']),
    );
  }
}

class AdminUsers {
  final int total;
  final int active;
  final int creators;
  final int freelancers;
  final int admins;
  final int superAdmins;
  final int suspended;
  final List<AdminUser> users;

  const AdminUsers({
    required this.total,
    required this.active,
    required this.creators,
    required this.freelancers,
    required this.admins,
    required this.superAdmins,
    required this.suspended,
    required this.users,
  });

  factory AdminUsers.fromJson(Map<String, dynamic> json) {
    return AdminUsers(
      total: _asInt(json['total']),
      active: _asInt(json['active']),
      creators: _asInt(json['creators']),
      freelancers: _asInt(json['freelancers']),
      admins: _asInt(json['admins']),
      superAdmins: _asInt(json['super_admins']),
      suspended: _asInt(json['suspended']),
      users: (json['users'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Admins management (super_admin only)
// ---------------------------------------------------------------------------

class AdminAccount {
  final String id;
  final String email;
  final String? username;
  final String role;
  final bool isActive;
  final String createdAt;

  const AdminAccount({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  bool get isSuperAdmin => role == 'super_admin';

  factory AdminAccount.fromJson(Map<String, dynamic> json) {
    return AdminAccount(
      id: _asString(json['id']),
      email: _asString(json['email']),
      username: json['username']?.toString(),
      role: _asString(json['role'], 'admin'),
      isActive: json['is_active'] != false,
      createdAt: _asString(json['created_at']),
    );
  }
}

class AdminAccounts {
  final int total;
  final int admins;
  final int superAdmins;
  final List<AdminAccount> accounts;

  const AdminAccounts({
    required this.total,
    required this.admins,
    required this.superAdmins,
    required this.accounts,
  });

  factory AdminAccounts.fromJson(Map<String, dynamic> json) {
    return AdminAccounts(
      total: _asInt(json['total']),
      admins: _asInt(json['admins']),
      superAdmins: _asInt(json['super_admins']),
      accounts: (json['accounts'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminAccount.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Freelancer applications (admin review)
// ---------------------------------------------------------------------------

class AdminApplication {
  final String id;
  final String userId;
  final String? username;
  final String? email;
  final String? avatarUrl;
  final String fullName;
  final String displayName;
  final String title;
  final List<String> skills;
  final String? experience;
  final List<String> portfolioLinks;
  final String? expectedPriceRange;
  final String? message;
  final String status;
  final String? adminNote;
  final String createdAt;
  final String? updatedAt;
  final String? reviewedAt;

  const AdminApplication({
    required this.id,
    required this.userId,
    required this.username,
    required this.email,
    required this.avatarUrl,
    required this.fullName,
    required this.displayName,
    required this.title,
    required this.skills,
    required this.experience,
    required this.portfolioLinks,
    required this.expectedPriceRange,
    required this.message,
    required this.status,
    required this.adminNote,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedAt,
  });

  factory AdminApplication.fromJson(Map<String, dynamic> json) {
    List<String> asStringList(dynamic value) => value is List
        ? value.map((e) => e.toString()).toList()
        : <String>[];

    final fullName = _asString(json['full_name']);
    final displayName = _asString(json['display_name']);
    return AdminApplication(
      id: _asString(json['id']),
      userId: _asString(json['user_id']),
      username: json['username']?.toString(),
      email: json['email']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      fullName: fullName,
      // Prefer display_name, fall back to full_name so the card is never blank.
      displayName: displayName.isNotEmpty ? displayName : fullName,
      title: _asString(json['title']),
      skills: asStringList(json['skills']),
      experience: json['experience']?.toString(),
      portfolioLinks: asStringList(json['portfolio_links']),
      expectedPriceRange: json['expected_price_range']?.toString(),
      message: json['message']?.toString(),
      status: _asString(json['status'], 'pending_review'),
      adminNote: json['admin_note']?.toString(),
      createdAt: _asString(json['created_at']),
      updatedAt: json['updated_at']?.toString(),
      reviewedAt: json['reviewed_at']?.toString(),
    );
  }
}

class AdminApplications {
  final int total;
  final int pending;
  final int approved;
  final int rejected;
  final List<AdminApplication> applications;

  const AdminApplications({
    required this.total,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.applications,
  });

  factory AdminApplications.fromJson(Map<String, dynamic> json) {
    final applications = (json['applications'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AdminApplication.fromJson)
        .toList();
    return AdminApplications(
      total: _asInt(json['total'] ?? applications.length),
      pending: _asInt(json['pending'] ??
          applications.where((a) => a.status == 'pending_review').length),
      approved: _asInt(json['approved'] ??
          applications.where((a) => a.status == 'approved').length),
      rejected: _asInt(json['rejected'] ??
          applications.where((a) => a.status == 'rejected').length),
      applications: applications,
    );
  }
}

// ---------------------------------------------------------------------------
// Marketplace console
// ---------------------------------------------------------------------------

class AdminAsset {
  final String id;
  final String title;
  final String creatorId;
  final String? creatorUsername;
  final String category;
  final String style;
  final String visibility;
  final bool isPaid;
  final int price;
  final String currency;
  final String? moderationStatus;
  final String? moderationReason;
  final String createdAt;

  const AdminAsset({
    required this.id,
    required this.title,
    required this.creatorId,
    this.creatorUsername,
    required this.category,
    required this.style,
    required this.visibility,
    required this.isPaid,
    required this.price,
    required this.currency,
    this.moderationStatus,
    this.moderationReason,
    required this.createdAt,
  });

  /// True once an admin has soft-removed the asset (hidden from marketplace).
  bool get isRemoved =>
      visibility == 'removed' || moderationStatus == 'removed';

  factory AdminAsset.fromJson(Map<String, dynamic> json) {
    return AdminAsset(
      id: _asString(json['id']),
      title: _asString(json['title']),
      creatorId: _asString(json['creator_id']),
      creatorUsername: json['creator_username']?.toString(),
      category: _asString(json['category']),
      style: _asString(json['style']),
      visibility: _asString(json['visibility'], 'draft'),
      isPaid: json['is_paid'] == true,
      price: _asInt(json['price']),
      currency: _asString(json['currency'], 'usd'),
      moderationStatus: json['moderation_status']?.toString(),
      moderationReason: json['moderation_reason']?.toString(),
      createdAt: _asString(json['created_at']),
    );
  }
}

/// Response of GET /admin/assets — the full moderation directory.
class AdminAssets {
  final int total;
  final int published;
  final int draft;
  final int removed;
  final List<AdminAsset> assets;

  const AdminAssets({
    required this.total,
    required this.published,
    required this.draft,
    required this.removed,
    required this.assets,
  });

  factory AdminAssets.fromJson(Map<String, dynamic> json) {
    return AdminAssets(
      total: _asInt(json['total']),
      published: _asInt(json['published']),
      draft: _asInt(json['draft']),
      removed: _asInt(json['removed']),
      assets: (json['assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminAsset.fromJson)
          .toList(),
    );
  }
}

class AdminMarketplace {
  final int totalAssets;
  final int published;
  final int draft;
  final int pendingReview;
  final int flagged;
  final int approvedToday;
  final int downloads;
  final int purchases;
  final List<AdminAsset> assets;

  const AdminMarketplace({
    required this.totalAssets,
    required this.published,
    required this.draft,
    required this.pendingReview,
    required this.flagged,
    required this.approvedToday,
    required this.downloads,
    required this.purchases,
    required this.assets,
  });

  factory AdminMarketplace.fromJson(Map<String, dynamic> json) {
    return AdminMarketplace(
      totalAssets: _asInt(json['total_assets']),
      published: _asInt(json['published']),
      draft: _asInt(json['draft']),
      pendingReview: _asInt(json['pending_review']),
      flagged: _asInt(json['flagged']),
      approvedToday: _asInt(json['approved_today']),
      downloads: _asInt(json['downloads']),
      purchases: _asInt(json['purchases']),
      assets: (json['assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminAsset.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Moderation hub
// ---------------------------------------------------------------------------

class AdminModeration {
  final int openReports;
  final int appeals;
  final int flaggedUsers;
  final int flaggedAssets;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> violations;

  const AdminModeration({
    required this.openReports,
    required this.appeals,
    required this.flaggedUsers,
    required this.flaggedAssets,
    required this.reports,
    required this.violations,
  });

  factory AdminModeration.fromJson(Map<String, dynamic> json) {
    return AdminModeration(
      openReports: _asInt(json['open_reports']),
      appeals: _asInt(json['appeals']),
      flaggedUsers: _asInt(json['flagged_users']),
      flaggedAssets: _asInt(json['flagged_assets']),
      reports: (json['reports'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      violations: (json['violations'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Freelancers directory
// ---------------------------------------------------------------------------

class AdminFreelancers {
  final int total;
  final int active;
  final int featured;
  final List<FreelanceProfile> freelancers;

  const AdminFreelancers({
    required this.total,
    required this.active,
    required this.featured,
    required this.freelancers,
  });

  factory AdminFreelancers.fromJson(Map<String, dynamic> json) {
    return AdminFreelancers(
      total: _asInt(json['total']),
      active: _asInt(json['active']),
      featured: _asInt(json['featured']),
      freelancers: (json['freelancers'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FreelanceProfile.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// System health
// ---------------------------------------------------------------------------

class AdminPipeline {
  final String name;
  final String status;

  const AdminPipeline({required this.name, required this.status});

  factory AdminPipeline.fromJson(Map<String, dynamic> json) {
    return AdminPipeline(
      name: _asString(json['name']),
      status: _asString(json['status'], 'unknown'),
    );
  }
}

class AdminSystem {
  final String backend;
  final String env;
  final String gpuStatus;
  final int queueSize;
  final String? storageUsed;
  final List<AdminPipeline> pipelines;
  // Rich live health payload from GET /admin/system. Read defensively so the
  // UI keeps working even if a sub-section is missing.
  final Map<String, dynamic> health;

  const AdminSystem({
    required this.backend,
    required this.env,
    required this.gpuStatus,
    required this.queueSize,
    required this.storageUsed,
    required this.pipelines,
    required this.health,
  });

  Map<String, dynamic> _section(String key) {
    final v = health[key];
    return v is Map<String, dynamic> ? v : const {};
  }

  Map<String, dynamic> get backendInfo => _section('backend');
  Map<String, dynamic> get database => _section('database');
  Map<String, dynamic> get redis => _section('redis');
  Map<String, dynamic> get celery => _section('celery');
  Map<String, dynamic> get storage => _section('storage');
  Map<String, dynamic> get aiPipeline => _section('ai_pipeline');
  Map<String, dynamic> get moderation => _section('marketplace_moderation');
  List<String> get warnings =>
      (health['warnings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
  String? get timestamp => health['timestamp']?.toString();
  bool get hasHealth => health.isNotEmpty;

  factory AdminSystem.fromJson(Map<String, dynamic> json) {
    return AdminSystem(
      backend: _asString(json['backend'], 'unknown'),
      env: _asString(json['env']),
      gpuStatus: _asString(json['gpu_status'], 'unknown'),
      queueSize: _asInt(json['queue_size']),
      storageUsed: json['storage_used']?.toString(),
      pipelines: (json['pipelines'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminPipeline.fromJson)
          .toList(),
      health: (json['health'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

// ---------------------------------------------------------------------------
// AI model management / jobs
// ---------------------------------------------------------------------------

class AdminJob {
  final String id;
  final String type;
  final String status;
  final int progress;
  final String createdAt;

  const AdminJob({
    required this.id,
    required this.type,
    required this.status,
    required this.progress,
    required this.createdAt,
  });

  factory AdminJob.fromJson(Map<String, dynamic> json) {
    return AdminJob(
      id: _asString(json['id']),
      type: _asString(json['type'], 'ai'),
      status: _asString(json['status'], 'queued'),
      progress: _asInt(json['progress']),
      createdAt: _asString(json['created_at']),
    );
  }
}

class AdminJobs {
  final int queue;
  final int processing;
  final int failed;
  final int completed;
  final int aiJobs;
  final int scanJobs;
  final int averageProgress;
  final List<AdminJob> recent;

  const AdminJobs({
    required this.queue,
    required this.processing,
    required this.failed,
    required this.completed,
    required this.aiJobs,
    required this.scanJobs,
    required this.averageProgress,
    required this.recent,
  });

  factory AdminJobs.fromJson(Map<String, dynamic> json) {
    return AdminJobs(
      queue: _asInt(json['queue']),
      processing: _asInt(json['processing']),
      failed: _asInt(json['failed']),
      completed: _asInt(json['completed']),
      aiJobs: _asInt(json['ai_jobs']),
      scanJobs: _asInt(json['scan_jobs']),
      averageProgress: _asInt(json['average_progress']),
      recent: (json['recent'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminJob.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class AdminService {
  AdminService(this._api);

  final ApiClient _api;

  Future<AdminSummary> summary() async {
    final data = await _api.getJson('/admin/summary', auth: true);
    return AdminSummary.fromJson(data);
  }

  /// List users with optional search/filter. [status] is 'active' | 'banned'.
  Future<AdminUsers> users({String? q, String? role, String? status}) async {
    final query = <String, String>{};
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    if (role != null && role.isNotEmpty && role != 'all') query['role'] = role;
    if (status != null && status.isNotEmpty && status != 'all') {
      query['status'] = status;
    }
    final data = await _api.getJson('/admin/users',
        auth: true, query: query.isEmpty ? null : query);
    return AdminUsers.fromJson(data);
  }

  // ----- User moderation -----

  Future<AdminAccount> banUser(String userId, {String? reason}) async {
    final data = await _api.postJson('/admin/users/$userId/ban',
        auth: true, body: {'reason': reason});
    return AdminAccount.fromJson(data);
  }

  Future<AdminAccount> unbanUser(String userId, {String? reason}) async {
    final data = await _api.postJson('/admin/users/$userId/unban',
        auth: true, body: {'reason': reason});
    return AdminAccount.fromJson(data);
  }

  /// Change a user's role (super_admin only on the backend).
  Future<AdminAccount> updateUserRole(String userId, String role) =>
      changeUserRole(userId, role);

  // ----- Asset / marketplace moderation -----

  Future<AdminAssets> listAssets({String? q, String? visibility}) async {
    final query = <String, String>{};
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    if (visibility != null && visibility.isNotEmpty && visibility != 'all') {
      query['visibility'] = visibility;
    }
    final data = await _api.getJson('/admin/assets',
        auth: true, query: query.isEmpty ? null : query);
    return AdminAssets.fromJson(data);
  }

  Future<AdminAsset> hideAsset(String assetId, {String? reason}) async {
    final data = await _api.postJson('/admin/assets/$assetId/hide',
        auth: true, body: {'reason': reason});
    return AdminAsset.fromJson(data);
  }

  Future<AdminAsset> restoreAsset(String assetId, {String? visibility}) async {
    final data = await _api.postJson('/admin/assets/$assetId/restore',
        auth: true, body: {'visibility': visibility});
    return AdminAsset.fromJson(data);
  }

  Future<void> deleteAsset(String assetId, {String? reason}) async {
    await _api.deleteJson('/admin/assets/$assetId',
        auth: true, body: {'reason': reason});
  }

  Future<AdminMarketplace> marketplace() async {
    final data = await _api.getJson('/admin/marketplace', auth: true);
    return AdminMarketplace.fromJson(data);
  }

  Future<AdminModeration> moderation() async {
    final data = await _api.getJson('/admin/moderation', auth: true);
    return AdminModeration.fromJson(data);
  }

  Future<AdminFreelancers> freelancers() async {
    final rows = await _api.getJsonList('/admin/freelance/freelancers', auth: true);
    final freelancers = rows
        .whereType<Map<String, dynamic>>()
        .map(FreelanceProfile.fromJson)
        .toList();
    return AdminFreelancers(
      total: freelancers.length,
      active: freelancers.where((f) => f.availability == 'available').length,
      featured: freelancers.where((f) => f.featured).length,
      freelancers: freelancers,
    );
  }

  Future<AdminSystem> system() async {
    final data = await _api.getJson('/admin/system', auth: true);
    return AdminSystem.fromJson(data);
  }

  Future<AdminJobs> jobs() async {
    final data = await _api.getJson('/admin/jobs', auth: true);
    return AdminJobs.fromJson(data);
  }

  // ----- Admins management (super_admin only) -----

  Future<AdminAccounts> admins() async {
    final data = await _api.getJson('/admin/admins', auth: true);
    return AdminAccounts.fromJson(data);
  }

  Future<AdminAccount> createAdmin({
    required String email,
    required String username,
    required String password,
  }) async {
    final data = await _api.postJson('/admin/admins', auth: true, body: {
      'email': email,
      'username': username,
      'password': password,
    });
    return AdminAccount.fromJson(data);
  }

  Future<AdminAccount> promoteToAdmin(String userId) async {
    final data = await _api.postJson('/admin/admins/promote',
        auth: true, body: {'user_id': userId});
    return AdminAccount.fromJson(data);
  }

  Future<AdminAccount> demoteAdmin(String userId) async {
    final data = await _api.postJson('/admin/admins/demote',
        auth: true, body: {'user_id': userId});
    return AdminAccount.fromJson(data);
  }

  Future<AdminAccount> changeUserRole(String userId, String role) async {
    final data = await _api.patchJson('/admin/users/$userId/role',
        auth: true, body: {'role': role});
    return AdminAccount.fromJson(data);
  }

  // ----- Freelancer applications -----

  Future<AdminApplications> freelancerApplications({String? status}) async {
    final query = (status != null && status.isNotEmpty && status != 'all')
        ? {'status': status}
        : null;
    final data = await _api.getJson('/admin/freelance/applications',
        auth: true, query: query);
    return AdminApplications.fromJson(data);
  }

  Future<void> approveApplication(String applicationId, {String? note}) async {
    await _api.patchJson(
      '/admin/freelance/applications/$applicationId/approve',
      auth: true,
      body: {'admin_note': note},
    );
  }

  Future<void> rejectApplication(String applicationId, {String? note}) async {
    await _api.patchJson(
      '/admin/freelance/applications/$applicationId/reject',
      auth: true,
      body: {'admin_note': note},
    );
  }

  Future<void> requestMoreInfo(String applicationId, {String? note}) async {
    await _api.patchJson(
      '/admin/freelance/applications/$applicationId/request-info',
      auth: true,
      body: {'admin_note': note},
    );
  }

  // ----- Freelancer profiles (suspend / reactivate) -----

  Future<List<FreelanceProfile>> freelanceProfiles({String? status}) async {
    final query = (status != null && status.isNotEmpty && status != 'all')
        ? {'status': status}
        : null;
    final rows = await _api.getJsonList('/admin/freelance/freelancers',
        auth: true, query: query);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(FreelanceProfile.fromJson)
        .toList();
  }

  Future<void> setFreelancerStatus(String freelancerId, String status) async {
    await _api.patchJson('/admin/freelance/freelancers/$freelancerId/status',
        auth: true, body: {'status': status});
  }

  // ----- Freelance services (moderation) -----

  Future<List<FlService>> freelanceServices({String? status}) async {
    final query = (status != null && status.isNotEmpty && status != 'all')
        ? {'status': status}
        : null;
    final rows = await _api.getJsonList('/admin/freelance/services',
        auth: true, query: query);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(FlService.fromJson)
        .toList();
  }

  Future<void> setServiceStatus(String serviceId, String status) async {
    await _api.patchJson('/admin/freelance/services/$serviceId/status',
        auth: true, body: {'status': status});
  }

  // ----- Freelance orders / disputes -----

  Future<List<FlOrder>> freelanceOrders({String? status}) async {
    final query = (status != null && status.isNotEmpty && status != 'all')
        ? {'status': status}
        : null;
    final rows = await _api.getJsonList('/admin/freelance/orders',
        auth: true, query: query);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(FlOrder.fromJson)
        .toList();
  }

  // ----- Freelance metrics -----

  Future<AdminFreelanceSummary> freelanceSummary() async {
    final data = await _api.getJson('/admin/freelance/summary', auth: true);
    return AdminFreelanceSummary.fromJson(data);
  }
}

/// Real freelance operations metrics from GET /admin/freelance/summary.
class AdminFreelanceSummary {
  final int applications;
  final int freelancers;
  final int services;
  final int orders;
  final int disputes;
  final int reviews;
  final double completedRevenue;
  final Map<String, int> ordersByStatus;

  const AdminFreelanceSummary({
    required this.applications,
    required this.freelancers,
    required this.services,
    required this.orders,
    required this.disputes,
    required this.reviews,
    required this.completedRevenue,
    required this.ordersByStatus,
  });

  int statusCount(String status) => ordersByStatus[status] ?? 0;

  factory AdminFreelanceSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['orders_by_status'];
    final byStatus = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) => byStatus[k.toString()] = _asInt(v));
    }
    return AdminFreelanceSummary(
      applications: _asInt(json['applications']),
      freelancers: _asInt(json['freelancers']),
      services: _asInt(json['services']),
      orders: _asInt(json['orders']),
      disputes: _asInt(json['disputes']),
      reviews: _asInt(json['reviews']),
      completedRevenue:
          double.tryParse(json['completed_revenue']?.toString() ?? '') ?? 0,
      ordersByStatus: byStatus,
    );
  }
}
