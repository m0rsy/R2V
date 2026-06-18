import 'dart:typed_data';

import 'api_client.dart';

double _double(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
int _int(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];
Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Map<String, dynamic>>[];

class FlUserMini {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? role;
  const FlUserMini({required this.id, this.username, this.displayName, this.avatarUrl, this.role});
  String get name => (displayName?.isNotEmpty == true) ? displayName! : (username ?? 'User');
  factory FlUserMini.fromJson(Map<String, dynamic> j) => FlUserMini(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString(),
        displayName: j['display_name']?.toString(),
        avatarUrl: j['avatar_url']?.toString(),
        role: j['role']?.toString(),
      );
  static FlUserMini? maybe(dynamic j) => j is Map ? FlUserMini.fromJson(j.cast<String, dynamic>()) : null;
}

class FreelanceProfile {
  final String id;
  final String userId;
  final String username;
  final String email;
  final String displayName;
  final String role;
  final String title;
  final String? bio;
  final String? avatarUrl;
  final String? coverUrl;
  final double rating;
  final int reviews;
  final String? hourlyRate;
  final String? startingPrice;
  final bool featured;
  final List<String> skills;
  final List<String> categories;
  final List<String> portfolioLinks;
  final String availability;
  final int completedJobs;
  final String status;
  final String createdAt;
  final List<FlService> services;

  const FreelanceProfile({
    required this.id,
    required this.userId,
    required this.username,
    required this.email,
    required this.displayName,
    required this.role,
    required this.title,
    this.bio,
    this.avatarUrl,
    this.coverUrl,
    required this.rating,
    required this.reviews,
    this.hourlyRate,
    this.startingPrice,
    required this.featured,
    required this.skills,
    required this.categories,
    required this.portfolioLinks,
    required this.availability,
    required this.completedJobs,
    this.status = '',
    this.createdAt = '',
    this.services = const [],
  });

  factory FreelanceProfile.fromJson(Map<String, dynamic> j) => FreelanceProfile(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        displayName: j['display_name']?.toString() ?? 'Freelancer',
        role: j['role']?.toString() ?? j['title']?.toString() ?? '3D Freelancer',
        title: j['title']?.toString() ?? '3D Freelancer',
        bio: j['bio']?.toString(),
        avatarUrl: j['avatar_url']?.toString() ?? j['profile_image']?.toString(),
        coverUrl: j['cover_url']?.toString(),
        rating: _double(j['rating_average'] ?? j['rating_avg'] ?? j['rating']),
        reviews: _int(j['rating_count'] ?? j['reviews_count'] ?? j['reviews']),
        hourlyRate: j['hourly_rate']?.toString(),
        startingPrice: j['starting_price']?.toString(),
        featured: j['featured'] == true,
        skills: _strings(j['skills']),
        categories: _strings(j['categories']),
        portfolioLinks: _strings(j['portfolio_links'] ?? j['portfolio']),
        availability: j['availability']?.toString() ?? 'available',
        completedJobs: _int(j['completed_jobs_count'] ?? j['completed_jobs']),
        status: j['status']?.toString() ?? '',
        createdAt: j['created_at']?.toString() ?? '',
        services: (j['services'] is List)
            ? (j['services'] as List).whereType<Map>().map((e) => FlService.fromJson(e.cast<String, dynamic>())).toList()
            : const [],
      );
}

typedef FlFreelancer = FreelanceProfile;

class FreelancerApplication {
  final String id;
  final String userId;
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

  const FreelancerApplication({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.title,
    required this.skills,
    this.experience,
    required this.portfolioLinks,
    this.expectedPriceRange,
    this.message,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory FreelancerApplication.fromJson(Map<String, dynamic> j) => FreelancerApplication(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        displayName: j['full_name']?.toString() ?? j['display_name']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        skills: _strings(j['skills']),
        experience: j['experience']?.toString(),
        portfolioLinks: _strings(j['portfolio_links']),
        expectedPriceRange: j['expected_price_range']?.toString(),
        message: j['message']?.toString(),
        status: j['status']?.toString() ?? 'pending_review',
        adminNote: j['admin_note']?.toString(),
        createdAt: j['created_at']?.toString() ?? '',
      );
}

class FlService {
  final String id;
  final String freelancerId;
  final FreelanceProfile? freelancer;
  final String title;
  final String description;
  final String category;
  final List<String> tags;
  final double startingPrice;
  final int deliveryDays;
  final int revisions;
  final List<String> fileFormats;
  final List<String> images;
  final String status;
  final String createdAt;

  const FlService({
    required this.id,
    required this.freelancerId,
    required this.freelancer,
    required this.title,
    required this.description,
    required this.category,
    required this.tags,
    required this.startingPrice,
    required this.deliveryDays,
    required this.revisions,
    required this.fileFormats,
    required this.images,
    required this.status,
    this.createdAt = '',
  });

  factory FlService.fromJson(Map<String, dynamic> j) => FlService(
        id: j['id']?.toString() ?? '',
        freelancerId: j['freelancer_id']?.toString() ?? '',
        freelancer: j['freelancer'] is Map ? FreelanceProfile.fromJson(_map(j['freelancer'])) : null,
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        category: j['category']?.toString() ?? '',
        tags: _strings(j['tags']),
        startingPrice: _double(j['starting_price']),
        deliveryDays: _int(j['delivery_days']),
        revisions: _int(j['revisions']),
        fileFormats: _strings(j['file_formats']),
        images: _strings(j['images']),
        status: j['status']?.toString() ?? 'active',
        createdAt: j['created_at']?.toString() ?? '',
      );
}

class FlOrder {
  final String id;
  final String clientId;
  final String freelancerId;
  final String? freelancerUserId;
  final String? serviceId;
  final FlUserMini? client;
  final FreelanceProfile? freelancer;
  final FlService? service;
  final String title;
  final String requirements;
  final double budget;
  final String? deadline;
  final List<String> attachments;
  final List<Map<String, dynamic>> deliveryFiles;
  final String status;
  final String? revisionNote;
  final String? disputeReason;
  final String? role;
  final bool canReview;
  final bool hasReviewed;
  final String createdAt;

  const FlOrder({
    required this.id,
    required this.clientId,
    required this.freelancerId,
    this.freelancerUserId,
    this.serviceId,
    this.client,
    this.freelancer,
    this.service,
    required this.title,
    required this.requirements,
    required this.budget,
    this.deadline,
    required this.attachments,
    required this.deliveryFiles,
    required this.status,
    this.revisionNote,
    this.disputeReason,
    this.role,
    required this.canReview,
    required this.hasReviewed,
    required this.createdAt,
  });

  bool get isClient => role == 'client';
  bool get isFreelancer => role == 'freelancer';

  factory FlOrder.fromJson(Map<String, dynamic> j) => FlOrder(
        id: j['id']?.toString() ?? '',
        clientId: j['client_id']?.toString() ?? '',
        freelancerId: j['freelancer_id']?.toString() ?? '',
        freelancerUserId: j['freelancer_user_id']?.toString(),
        serviceId: j['service_id']?.toString(),
        client: FlUserMini.maybe(j['client']),
        freelancer: j['freelancer'] is Map ? FreelanceProfile.fromJson(_map(j['freelancer'])) : null,
        service: j['service'] is Map ? FlService.fromJson(_map(j['service'])) : null,
        title: j['title']?.toString() ?? '',
        requirements: j['requirements']?.toString() ?? j['description']?.toString() ?? '',
        budget: _double(j['budget'] ?? j['price']),
        deadline: j['deadline']?.toString(),
        attachments: _strings(j['attachments']),
        deliveryFiles: _maps(j['delivery_files'] ?? j['deliverables']),
        status: j['status']?.toString() ?? 'pending',
        revisionNote: j['revision_note']?.toString(),
        disputeReason: j['dispute_reason']?.toString(),
        role: j['role']?.toString(),
        canReview: j['can_review'] == true,
        hasReviewed: j['has_reviewed'] == true,
        createdAt: j['created_at']?.toString() ?? '',
      );
}

class FlMessage {
  final String id;
  final String orderId;
  final String body;
  final bool isMine;
  final FlUserMini? sender;
  final List<Map<String, dynamic>> attachments;
  final String? voiceNoteUrl;
  final String createdAt;
  const FlMessage({
    required this.id,
    required this.orderId,
    required this.body,
    required this.isMine,
    required this.sender,
    required this.attachments,
    this.voiceNoteUrl,
    required this.createdAt,
  });
  factory FlMessage.fromJson(Map<String, dynamic> j) => FlMessage(
        id: j['id']?.toString() ?? '',
        orderId: j['order_id']?.toString() ?? j['conversation_id']?.toString() ?? '',
        body: j['message']?.toString() ?? j['body']?.toString() ?? '',
        isMine: j['is_mine'] == true,
        sender: FlUserMini.maybe(j['sender']),
        attachments: _maps(j['attachments']),
        voiceNoteUrl: j['voice_note_url']?.toString(),
        createdAt: j['created_at']?.toString() ?? '',
      );
}

class FlReview {
  final String id;
  final String orderId;
  final int rating;
  final int qualityRating;
  final int communicationRating;
  final int deliveryRating;
  final String? comment;
  final String createdAt;
  const FlReview({
    required this.id,
    required this.orderId,
    required this.rating,
    required this.qualityRating,
    required this.communicationRating,
    required this.deliveryRating,
    this.comment,
    required this.createdAt,
  });
  factory FlReview.fromJson(Map<String, dynamic> j) => FlReview(
        id: j['id']?.toString() ?? '',
        orderId: j['order_id']?.toString() ?? '',
        rating: _int(j['rating']),
        qualityRating: _int(j['quality_rating']),
        communicationRating: _int(j['communication_rating']),
        deliveryRating: _int(j['delivery_rating']),
        comment: j['comment']?.toString(),
        createdAt: j['created_at']?.toString() ?? '',
      );
}

class FlDashboard {
  final bool isFreelancer;
  final FreelanceProfile? profile;
  final int activeOrders;
  final int incomingOrders;
  final int completedJobs;
  final double earnings;
  final int serviceCount;
  final double rating;
  final int clientOrders;
  final double totalSpent;
  final int pendingDeliveries;
  const FlDashboard({
    required this.isFreelancer,
    required this.profile,
    required this.activeOrders,
    required this.incomingOrders,
    required this.completedJobs,
    required this.earnings,
    required this.serviceCount,
    required this.rating,
    required this.clientOrders,
    required this.totalSpent,
    required this.pendingDeliveries,
  });
  factory FlDashboard.fromJson(Map<String, dynamic> j) {
    final f = _map(j['freelancer']);
    final c = _map(j['client']);
    return FlDashboard(
      isFreelancer: j['is_freelancer'] == true,
      profile: j['profile'] is Map ? FreelanceProfile.fromJson(_map(j['profile'])) : null,
      activeOrders: _int(f['active_orders']),
      incomingOrders: _int(f['incoming_orders']),
      completedJobs: _int(f['completed_jobs']),
      earnings: _double(f['earnings']),
      serviceCount: _int(f['service_count']),
      rating: _double(f['rating']),
      clientOrders: _int(c['active_projects']),
      totalSpent: _double(c['total_spent']),
      pendingDeliveries: _int(c['pending_deliveries']),
    );
  }
}

class FreelanceService {
  FreelanceService(this._api);
  final ApiClient _api;

  Future<List<String>> categories() async {
    final rows = await _api.getJsonList('/freelance/categories');
    return rows.whereType<Map>().map((e) => e['name'].toString()).toList();
  }

  Future<List<FreelanceProfile>> profiles({String search = ''}) => freelancers(search: search);

  Future<List<FreelanceProfile>> freelancers({
    String search = '',
    String? category,
    String? skill,
    double? minRating,
    double? maxPrice,
    String? availability,
  }) async {
    final q = <String, String>{};
    if (search.trim().isNotEmpty) q['search'] = search.trim();
    if (category?.isNotEmpty == true) q['category'] = category!;
    if (skill?.isNotEmpty == true) q['skill'] = skill!;
    if (minRating != null && minRating > 0) q['min_rating'] = '$minRating';
    if (maxPrice != null) q['max_price'] = '$maxPrice';
    if (availability?.isNotEmpty == true) q['availability'] = availability!;
    final rows = await _api.getJsonList('/freelance/freelancers', query: q.isEmpty ? null : q);
    return rows.whereType<Map>().map((e) => FreelanceProfile.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<FreelanceProfile> freelancer(String id) async =>
      FreelanceProfile.fromJson(await _api.getJson('/freelance/freelancers/$id'));

  Future<List<FlService>> services({String search = '', String? category}) async {
    final q = <String, String>{};
    if (search.trim().isNotEmpty) q['search'] = search.trim();
    if (category?.isNotEmpty == true) q['category'] = category!;
    final rows = await _api.getJsonList('/freelance/services', query: q.isEmpty ? null : q);
    return rows.whereType<Map>().map((e) => FlService.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<FlService> service(String id) async =>
      FlService.fromJson(await _api.getJson('/freelance/services/$id'));

  Future<FreelancerApplication> apply({
    required String fullName,
    required String title,
    List<String> skills = const [],
    String? experience,
    List<String> portfolioLinks = const [],
    String? expectedPriceRange,
    String? message,
  }) async {
    final data = await _api.postJson('/freelance/apply', auth: true, body: {
      'full_name': fullName,
      'title': title,
      'skills': skills,
      'experience': experience,
      'portfolio_links': portfolioLinks,
      'expected_price_range': expectedPriceRange,
      'message': message,
    });
    return FreelancerApplication.fromJson(data);
  }

  Future<FreelancerApplication?> myApplication() async {
    final data = await _api.getJson('/freelance/my-application', auth: true);
    if (data['id'] == null) return null;
    return FreelancerApplication.fromJson(data);
  }

  Future<FlDashboard> dashboardSummary() async =>
      FlDashboard.fromJson(await _api.getJson('/freelance/dashboard', auth: true));
  Future<Map<String, dynamic>> dashboard() => _api.getJson('/freelance/dashboard', auth: true);

  Future<FreelanceProfile?> myFreelancerProfile() async {
    final data = await _api.getJson('/freelance/profile/me', auth: true);
    return data['id'] == null ? null : FreelanceProfile.fromJson(data);
  }

  Future<FreelanceProfile> upsertMyProfile(Map<String, dynamic> body) async =>
      FreelanceProfile.fromJson(await _api.patchJson('/freelance/profile', auth: true, body: body));

  Future<FreelanceProfile> updateAvailability(String availability) async =>
      FreelanceProfile.fromJson(await _api.patchJson('/freelance/availability', auth: true, body: {'availability': availability}));

  Future<FlService> createService(Map<String, dynamic> body) async =>
      FlService.fromJson(await _api.postJson('/freelance/services', auth: true, body: body));

  Future<FlService> updateService(String id, Map<String, dynamic> body) async =>
      FlService.fromJson(await _api.patchJson('/freelance/services/$id', auth: true, body: body));

  Future<void> deleteService(String id) async {
    await _api.deleteJson('/freelance/services/$id', auth: true);
  }

  Future<FlOrder> createOrder(Map<String, dynamic> body) async =>
      FlOrder.fromJson(await _api.postJson('/freelance/orders', auth: true, body: body));

  Future<List<FlOrder>> orders({String? status, String? role}) async {
    final q = <String, String>{};
    if (status?.isNotEmpty == true) q['status'] = status!;
    final rows = await _api.getJsonList('/freelance/my-orders', auth: true, query: q.isEmpty ? null : q);
    return rows.whereType<Map>().map((e) => FlOrder.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<List<FlOrder>> incomingOrders() async {
    final rows = await _api.getJsonList('/freelance/incoming-orders', auth: true);
    return rows.whereType<Map>().map((e) => FlOrder.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<FlOrder> order(String id) async =>
      FlOrder.fromJson(await _api.getJson('/freelance/orders/$id', auth: true));

  Future<FlOrder> acceptOrder(String id) async =>
      FlOrder.fromJson(await _api.patchJson('/freelance/orders/$id/accept', auth: true));
  Future<FlOrder> rejectOrder(String id) async =>
      FlOrder.fromJson(await _api.patchJson('/freelance/orders/$id/reject', auth: true));
  Future<FlOrder> requestRevision(String id, String note) async =>
      FlOrder.fromJson(await _api.postJson('/freelance/orders/$id/request-revision', auth: true, body: {'note': note}));
  Future<FlOrder> completeOrder(String id) async =>
      FlOrder.fromJson(await _api.postJson('/freelance/orders/$id/complete', auth: true));
  Future<FlOrder> approveOrder(String id) => completeOrder(id);
  Future<FlOrder> deliverOrder(String id, {String? message, List<String> files = const []}) async =>
      FlOrder.fromJson(await _api.postJson('/freelance/orders/$id/deliver', auth: true, body: {'message': message, 'files': files}));
  Future<FlOrder> disputeOrder(String id, String reason) async =>
      FlOrder.fromJson(await _api.patchJson('/freelance/orders/$id/status', auth: true, body: {'status': 'disputed', 'reason': reason}));
  Future<FlOrder> cancelOrder(String id) async =>
      FlOrder.fromJson(await _api.patchJson('/freelance/orders/$id/status', auth: true, body: {'status': 'cancelled'}));

  Future<FlReview> reviewOrder(String id, {required int rating, String? comment}) async =>
      FlReview.fromJson(await _api.postJson('/freelance/orders/$id/review', auth: true, body: {
        'rating': rating,
        'quality_rating': rating,
        'communication_rating': rating,
        'delivery_rating': rating,
        'comment': comment,
      }));

  Future<List<FlMessage>> messages(String orderId) async {
    final data = await _api.getJson('/freelance/orders/$orderId/messages', auth: true);
    return (data['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => FlMessage.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<FlMessage> sendMessage({required String orderId, required String text}) async =>
      FlMessage.fromJson(await _api.postJson('/freelance/orders/$orderId/messages', auth: true, body: {'message': text}));

  Future<FlMessage> uploadMessageAttachment({
    required String orderId,
    required List<int> fileBytes,
    required String fileName,
    String? contentType,
    bool voice = false,
  }) async {
    final data = await _api.postMultipart(
      '/freelance/orders/$orderId/messages/${voice ? 'voice-note' : 'attachment'}',
      fileBytes: Uint8List.fromList(fileBytes),
      fileName: fileName,
      contentType: contentType,
    );
    return FlMessage.fromJson(data);
  }
}
