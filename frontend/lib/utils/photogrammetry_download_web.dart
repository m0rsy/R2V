// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:http/http.dart' as http;

Future<String> savePhotogrammetryDownloadImpl({
  required String url,
  required String filename,
  required http.Client client,
}) async {
  html.AnchorElement(href: url)
    ..download = filename
    ..target = '_blank'
    ..click();
  return filename;
}
