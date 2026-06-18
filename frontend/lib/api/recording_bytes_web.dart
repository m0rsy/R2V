import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Web: `record` returns a `blob:` URL. Fetch its bytes via XHR.
Future<Uint8List> readRecordingBytes(String url) async {
  final res = await http.get(Uri.parse(url));
  return res.bodyBytes;
}
