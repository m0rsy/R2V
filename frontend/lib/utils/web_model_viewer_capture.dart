import 'dart:typed_data';

import 'web_model_viewer_capture_stub.dart'
    if (dart.library.html) 'web_model_viewer_capture_web.dart';

Future<Uint8List?> captureModelViewerPng(String elementId) =>
    captureModelViewerPngImpl(elementId);
