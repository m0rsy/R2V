import 'package:http/http.dart' as http;

import 'photogrammetry_download_io.dart'
    if (dart.library.html) 'photogrammetry_download_web.dart';

Future<String> savePhotogrammetryDownload({
  required String url,
  required String filename,
  required http.Client client,
}) {
  return savePhotogrammetryDownloadImpl(
    url: url,
    filename: filename,
    client: client,
  );
}
