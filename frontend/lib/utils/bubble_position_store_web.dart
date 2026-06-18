// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui' show Offset;

// Keys match the requested convention.
const String _kX = 'r2v.chatBubble.x';
const String _kY = 'r2v.chatBubble.y';

Future<Offset?> loadBubblePositionImpl() async {
  try {
    final xs = html.window.localStorage[_kX];
    final ys = html.window.localStorage[_kY];
    if (xs == null || ys == null) return null;
    final x = double.tryParse(xs);
    final y = double.tryParse(ys);
    if (x == null || y == null) return null;
    // Defensive clamp: only ever return a sane 0..1 fraction.
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  } catch (_) {
    return null;
  }
}

Future<void> saveBubblePositionImpl(double x, double y) async {
  try {
    html.window.localStorage[_kX] = x.clamp(0.0, 1.0).toString();
    html.window.localStorage[_kY] = y.clamp(0.0, 1.0).toString();
  } catch (_) {
    // Storage may be unavailable (private mode / quota); ignore silently.
  }
}
