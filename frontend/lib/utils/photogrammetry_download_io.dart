import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Future<String> savePhotogrammetryDownloadImpl({
  required String url,
  required String filename,
  required http.Client client,
}) async {
  final response = await client.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Download failed (${response.statusCode})');
  }

  final baseDir = await getApplicationDocumentsDirectory();
  final targetDir = Directory('${baseDir.path}${Platform.pathSeparator}photogrammetry_downloads');
  if (!targetDir.existsSync()) {
    targetDir.createSync(recursive: true);
  }

  final file = File('${targetDir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(response.bodyBytes, flush: true);
  return file.path;
}
