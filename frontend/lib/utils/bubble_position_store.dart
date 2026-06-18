import 'dart:ui' show Offset;

import 'bubble_position_store_stub.dart'
    if (dart.library.html) 'bubble_position_store_web.dart';

/// Persisted position of the floating chat bubble, stored as NORMALIZED
/// fractions (0..1) of the screen width/height so it survives window/zoom
/// changes and different devices. Backed by `window.localStorage` on web and a
/// no-op elsewhere. Returns null when nothing has been saved yet.
Future<Offset?> loadBubblePosition() => loadBubblePositionImpl();

Future<void> saveBubblePosition(double xFraction, double yFraction) =>
    saveBubblePositionImpl(xFraction, yFraction);
