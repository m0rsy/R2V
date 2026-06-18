import 'api_config_impl.dart';

// Use pure-Dart Uri.base instead of deprecated dart:html.
// Uri.base on the web platform returns the current page URL;
// .origin yields scheme + host + port (e.g. "https://app.example.com").
class ApiConfigImpl implements ApiConfigBase {
  @override
  String get origin => Uri.base.origin;
}
