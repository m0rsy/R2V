import 'dart:ui' show Offset;

// Non-web fallback: no persistence (the bubble simply defaults each launch).
Future<Offset?> loadBubblePositionImpl() async => null;

Future<void> saveBubblePositionImpl(double x, double y) async {}
