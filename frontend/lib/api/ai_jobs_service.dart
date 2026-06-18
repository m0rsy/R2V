import 'api_client.dart';

/// Generation input modes supported by the R2V AI pipeline.
enum GenerationInputType { prompt, voice, image }

extension GenerationInputTypeWire on GenerationInputType {
  String get wire => switch (this) {
    GenerationInputType.prompt => 'prompt',
    GenerationInputType.voice => 'voice',
    GenerationInputType.image => 'image',
  };
}

class AiJob {
  final String id;
  final String status;
  final int progress;
  // Live AI generation progress (mirrored from Modal while running).
  final String? stage;
  final String? message;
  final String createdAt;
  final String? updatedAt;
  final String? error;
  final String? prompt;
  final String? inputType;
  // Requested texture preference for this job.
  final bool? withTexture;
  // Whether the returned model is actually textured (set once succeeded).
  final bool? textured;
  // Resolved model URLs (presigned) once the job has succeeded.
  final String? modelUrl;
  final String? glbUrl;
  final String? downloadUrl;
  // Freshly presigned URL for the job's stored input/preview image. Used to
  // restore an uploaded AI-chat image after the original URL expired.
  final String? outputImageUrl;
  // Optional sidecar artifacts reported by the Modal pipeline.
  final String? rawGlbUrl;
  final String? conditionImageUrl;
  final String? texturePngUrl;
  final String? textureDebugUrl;
  final Map<String, dynamic> artifacts;

  const AiJob({
    required this.id,
    required this.status,
    required this.progress,
    required this.createdAt,
    this.stage,
    this.message,
    this.updatedAt,
    this.error,
    this.prompt,
    this.inputType,
    this.withTexture,
    this.textured,
    this.modelUrl,
    this.glbUrl,
    this.downloadUrl,
    this.outputImageUrl,
    this.rawGlbUrl,
    this.conditionImageUrl,
    this.texturePngUrl,
    this.textureDebugUrl,
    this.artifacts = const {},
  });

  /// The best available direct model link from the status payload, if any.
  String? get bestModelUrl => (modelUrl != null && modelUrl!.isNotEmpty)
      ? modelUrl
      : (glbUrl != null && glbUrl!.isNotEmpty)
      ? glbUrl
      : (downloadUrl != null && downloadUrl!.isNotEmpty)
      ? downloadUrl
      : null;

  factory AiJob.fromJson(Map<String, dynamic> json) {
    String? str(String key) {
      final v = json[key];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    return AiJob(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      stage: str('stage'),
      message: str('message'),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString(),
      error: str('error'),
      prompt: json['prompt']?.toString(),
      inputType: json['input_type']?.toString(),
      withTexture: json['with_texture'] as bool?,
      textured: json['textured'] as bool?,
      modelUrl: str('model_url'),
      glbUrl: str('glb_url'),
      downloadUrl: str('download_url'),
      outputImageUrl: str('output_image_url'),
      rawGlbUrl: str('raw_glb_url'),
      conditionImageUrl: str('condition_image_url'),
      texturePngUrl: str('texture_png_url'),
      textureDebugUrl: str('texture_debug_url'),
      artifacts: json['artifacts'] is Map
          ? Map<String, dynamic>.from(json['artifacts'] as Map)
          : const {},
    );
  }
}

class AiJobsService {
  AiJobsService(this._api);

  final ApiClient _api;

  Future<AiJob> createJob({
    required String prompt,
    GenerationInputType inputType = GenerationInputType.prompt,
    bool withTexture = true,
    Map<String, dynamic>? settings,
  }) async {
    final data = await _api.postJson(
      '/ai/jobs',
      auth: true,
      body: {
        'prompt': prompt,
        'input_type': inputType.wire,
        'with_texture': withTexture,
        'settings': settings ?? {},
      },
    );
    return AiJob.fromJson(data);
  }

  Future<List<AiJob>> listJobs({int limit = 20, int offset = 0}) async {
    final list = await _api.getJsonList(
      '/ai/jobs',
      auth: true,
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return list.whereType<Map<String, dynamic>>().map(AiJob.fromJson).toList();
  }

  Future<AiJob> getJob(String jobId) async {
    final data = await _api.getJson('/ai/jobs/$jobId', auth: true);
    return AiJob.fromJson(data);
  }

  Future<String> downloadGlb(String jobId) async {
    final data = await _api.getJson('/ai/jobs/$jobId/download/glb', auth: true);
    return data['url']?.toString() ?? '';
  }
}
