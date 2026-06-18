// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';

/// Capture a PNG of the live `model-viewer` at the EXACT angle the user has
/// chosen.
///
/// We deliberately do NOT touch camera-orbit / camera-target / field-of-view:
/// `toDataURL()` reads whatever is currently on the canvas, so the saved
/// thumbnail preserves the user's framing. We only wait a moment for any
/// in-flight render (e.g. the frame right after a drag) to settle before
/// grabbing the pixels, and we leave the camera exactly where the user left it.
Future<Uint8List?> captureModelViewerPngImpl(String elementId) async {
  final element = html.document.querySelector('#$elementId');
  if (element == null) return null;
  final viewer = js.JsObject.fromBrowserObject(element);
  if (!viewer.hasProperty('toDataURL')) return null;

  // Nudge a render and let the current view settle (no camera changes).
  try {
    if (viewer.hasProperty('requestRender')) {
      viewer.callMethod('requestRender');
    }
  } catch (_) {
    // Older model-viewer builds may not expose requestRender; ignore.
  }
  await Future<void>.delayed(const Duration(milliseconds: 120));

  final dataUrl = viewer.callMethod('toDataURL') as String?;
  if (dataUrl == null) return null;
  if (dataUrl.isEmpty) return null;
  final parts = dataUrl.split(',');
  if (parts.length < 2) return null;
  return base64Decode(parts[1]);
}
