import 'package:flutter/foundation.dart';

import 'api_config_memory.dart'
  if (dart.library.html) 'api_config_web.dart';

class ApiConfig {
  /// Base URL for the FastAPI backend.
  ///
  /// - Dev: pass via --dart-define=R2V_API_BASE_URL=http://localhost:18001
  /// - Prod: pass your deployed API origin (e.g. https://api.example.com)
  static String get baseUrl {
    const defined = String.fromEnvironment('R2V_API_BASE_URL');
    if (defined.isNotEmpty) return _normalize(defined);

    // Default:
    if (kDebugMode) return 'http://localhost:18001';
    return _normalize(ApiConfigImpl().origin);
  }

  static String _normalize(String url) {
    if (url.endsWith('/')) return url.substring(0, url.length - 1);
    return url;
  }
}

abstract class ApiConfigBase {
  String get origin;
}
