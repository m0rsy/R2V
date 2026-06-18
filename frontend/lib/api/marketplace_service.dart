import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';

class MarketplaceAsset {
  final String id;
  final String title;
  final String description;
  final List<String> tags;
  final String category;
  final String style;
  final String creatorId;
  final bool isPaid;
  final int price;
  final String currency;
  final String? thumbObjectKey;
  final String? modelObjectKey;
  final String? thumbUrl;
  final String? previewUrl;
  final Map<String, dynamic> metadata;
  // Per-user state resolved by the backend for the current request.
  final bool likedByMe;
  final bool savedByMe;
  final int likesCount;

  const MarketplaceAsset({
    required this.id,
    required this.title,
    required this.description,
    required this.tags,
    required this.category,
    required this.style,
    required this.creatorId,
    required this.isPaid,
    required this.price,
    required this.currency,
    required this.thumbObjectKey,
    required this.modelObjectKey,
    required this.thumbUrl,
    required this.previewUrl,
    required this.metadata,
    this.likedByMe = false,
    this.savedByMe = false,
    this.likesCount = 0,
  });

  factory MarketplaceAsset.fromJson(Map<String, dynamic> json) {
    final meta = (json['metadata'] as Map<String, dynamic>? ?? {});
    int parseLikes() {
      final top = json['likes_count'];
      if (top is num) return top.toInt();
      final m = meta['likes'];
      if (m is num) return m.toInt();
      return int.tryParse(m?.toString() ?? '') ?? 0;
    }

    return MarketplaceAsset(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      category: json['category']?.toString() ?? '',
      style: json['style']?.toString() ?? '',
      creatorId: json['creator_id']?.toString() ?? '',
      isPaid: json['is_paid'] == true,
      price: (json['price'] ?? 0) as int,
      currency: json['currency']?.toString() ?? 'usd',
      thumbObjectKey: json['thumb_object_key']?.toString(),
      modelObjectKey: json['model_object_key']?.toString(),
      thumbUrl: json['thumb_url']?.toString(),
      previewUrl: json['preview_url']?.toString(),
      metadata: meta,
      likedByMe: json['liked_by_me'] == true,
      savedByMe: json['saved_by_me'] == true,
      likesCount: parseLikes(),
    );
  }

  String get author => metadata['creator_username']?.toString() ?? 'Unknown';

  String get likes => likesCount.toString();
}

class MarketplaceService {
  MarketplaceService(this._api);

  final ApiClient _api;

  Future<List<MarketplaceAsset>> listAssets({
    String? query,
    String? category,
    String? style,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (query != null && query.isNotEmpty) params['q'] = query;
    if (category != null && category.isNotEmpty && category != 'All') {
      params['category'] = category;
    }
    if (style != null && style.isNotEmpty && style != 'All') {
      params['style'] = style;
    }

    // auth:true sends the bearer token when signed in (so the backend can
    // resolve liked_by_me/saved_by_me) while staying fully browsable when
    // anonymous — _headers simply omits the header if there is no token.
    final list = await _api.getJsonList('/marketplace/assets', auth: true, query: params);
    return list
        .whereType<Map<String, dynamic>>()
        .map(MarketplaceAsset.fromJson)
        .toList();
  }

  Future<List<MarketplaceAsset>> listMyAssets() async {
    final list = await _api.getJsonList('/marketplace/assets/me', auth: true);
    return list
        .whereType<Map<String, dynamic>>()
        .map(MarketplaceAsset.fromJson)
        .toList();
  }

  Future<List<MarketplaceAsset>> listSavedAssets() async {
    final list = await _api.getJsonList('/marketplace/assets/saved', auth: true);
    return list
        .whereType<Map<String, dynamic>>()
        .map(MarketplaceAsset.fromJson)
        .toList();
  }

  Future<List<MarketplaceAsset>> listUserAssets(String userId) async {
    final list = await _api.getJsonList('/marketplace/assets/user/$userId', auth: true);
    return list
        .whereType<Map<String, dynamic>>()
        .map(MarketplaceAsset.fromJson)
        .toList();
  }

  Future<List<MarketplaceAsset>> listLikedAssets() async {
    final list = await _api.getJsonList('/marketplace/assets/liked', auth: true);
    return list
        .whereType<Map<String, dynamic>>()
        .map(MarketplaceAsset.fromJson)
        .toList();
  }

  /// Fetch a single asset by id (used by the `/explore?asset=<id>` deep link to
  /// open the detail modal when the asset isn't already in the loaded grid).
  Future<MarketplaceAsset> getAsset(String assetId) async {
    final data = await _api.getJson('/marketplace/assets/$assetId', auth: true);
    return MarketplaceAsset.fromJson(data);
  }

  /// Stable, shareable public link to an asset's detail view. Contains only the
  /// asset id — never a presigned/GLB URL. Uses the web hash route so it opens
  /// the Explore page and auto-selects the asset.
  static String shareUrlFor(String assetId) =>
      'https://realtwovirtual.com/#/explore?asset=$assetId';

  Future<String> checkoutAsset(String assetId) async {
    final data = await _api.postJson('/billing/checkout/asset',
        auth: true, body: {'asset_id': assetId});
    return data['checkout_url']?.toString() ?? '';
  }

  Future<String> downloadAsset(String assetId, {String? format}) async {
    final query = <String, String>{};
    if (format != null && format.trim().isNotEmpty) {
      query['format'] = format.trim();
    }
    final data = await _api.getJson('/assets/$assetId/download', auth: true, query: query.isEmpty ? null : query);
    return data['url']?.toString() ?? '';
  }

  Future<Map<String, String>> presignAssetUpload({
    required String filename,
    required String contentType,
    required String kind,
  }) async {
    final data = await _api.postJson(
      '/marketplace/assets/presign',
      auth: true,
      body: {
        'filename': filename,
        'content_type': contentType,
        'kind': kind,
      },
    );
    return {
      'url': data['url']?.toString() ?? '',
      'key': data['key']?.toString() ?? '',
    };
  }

  Future<void> uploadToPresignedUrl(String url, Uint8List bytes, {String? contentType}) async {
    final res = await http.put(
      Uri.parse(url),
      headers: contentType == null || contentType.isEmpty
          ? const {}
          : {'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = res.body.trim();
      final suffix = detail.isEmpty ? '' : ': $detail';
      throw Exception('Upload failed (${res.statusCode})$suffix');
    }
  }

  Future<MarketplaceAsset> createAsset({
    required String title,
    required String description,
    required List<String> tags,
    required String category,
    required String style,
    required bool isPaid,
    required int price,
    required String currency,
    required String modelObjectKey,
    required String? thumbObjectKey,
    required List<String> previewObjectKeys,
    Map<String, dynamic>? metadata,
  }) async {
    final data = await _api.postJson(
      '/marketplace/assets',
      auth: true,
      body: {
        'title': title,
        'description': description,
        'tags': tags,
        'category': category,
        'style': style,
        'is_paid': isPaid,
        'price': price,
        'currency': currency,
        'model_object_key': modelObjectKey,
        'thumb_object_key': thumbObjectKey,
        'preview_object_keys': previewObjectKeys,
        'metadata': metadata ?? {},
      },
    );
    return MarketplaceAsset.fromJson(data);
  }

  Future<MarketplaceAsset> publishAsset(String assetId) async {
    final data = await _api.postJson('/marketplace/assets/$assetId/publish', auth: true);
    return MarketplaceAsset.fromJson(data);
  }

  Future<MarketplaceAsset> createFromPhotogrammetryJob({
    required String jobId,
    required String title,
    required bool publish,
    String description = '',
    String? thumbObjectKey,
  }) async {
    final data = await _api.postJson(
      '/api/photogrammetry/jobs/$jobId/asset',
      auth: true,
      body: {
        'title': title,
        'description': description.isEmpty ? null : description,
        'tags': ['photogrammetry', 'scan'],
        'category': 'Scans',
        'style': 'Photogrammetry',
        'is_paid': false,
        'price': 0,
        'currency': 'usd',
        'publish': publish,
        'thumb_object_key': thumbObjectKey,
      },
    );
    return MarketplaceAsset.fromJson(data);
  }

  /// Publishes a succeeded AI job's generated GLB straight to the marketplace.
  /// The backend resolves the model/thumbnail object keys from the owned job
  /// row (never trusts client keys) and copies them into the marketplace bucket.
  Future<MarketplaceAsset> createFromAiJob({
    required String jobId,
    required String title,
    String description = '',
    List<String> tags = const [],
    String category = 'Objects',
    String style = 'AI Generated',
    bool isPaid = false,
    int price = 0,
    String currency = 'usd',
    bool publish = true,
    bool includeThumbnail = true,
    String? thumbObjectKey,
    bool repost = false,
  }) async {
    final data = await _api.postJson(
      '/ai/jobs/$jobId/asset',
      auth: true,
      body: {
        'title': title,
        'description': description.isEmpty ? null : description,
        'tags': tags,
        'category': category,
        'style': style,
        'is_paid': isPaid,
        'price': price,
        'currency': currency,
        'publish': publish,
        'include_thumbnail': includeThumbnail,
        if (thumbObjectKey != null) 'thumb_object_key': thumbObjectKey,
        'repost': repost,
      },
    );
    return MarketplaceAsset.fromJson(data);
  }

  Future<void> likeAsset(String assetId) async {
    await _api.postJson('/marketplace/assets/$assetId/like', auth: true);
  }

  Future<void> unlikeAsset(String assetId) async {
    await _api.deleteJson('/marketplace/assets/$assetId/like', auth: true);
  }

  Future<void> saveAsset(String assetId) async {
    await _api.postJson('/marketplace/assets/$assetId/save', auth: true);
  }

  Future<void> unsaveAsset(String assetId) async {
    await _api.deleteJson('/marketplace/assets/$assetId/save', auth: true);
  }

  Future<void> deleteAsset(String assetId) async {
    await _api.deleteJson('/marketplace/assets/$assetId', auth: true);
  }
}
