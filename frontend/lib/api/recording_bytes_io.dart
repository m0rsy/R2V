import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Native: `record` writes to a file path. Fall back to HTTP if a URL is given.
Future<Uint8List> readRecordingBytes(String pathOrUrl) async {
  if (pathOrUrl.startsWith('http') || pathOrUrl.startsWith('blob')) {
    final res = await http.get(Uri.parse(pathOrUrl));
    return res.bodyBytes;
  }
  return File(pathOrUrl).readAsBytes();
}
