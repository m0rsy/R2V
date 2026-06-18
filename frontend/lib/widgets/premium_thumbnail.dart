import 'package:flutter/material.dart';

/// Marketplace / asset card thumbnail.
///
/// 3D thumbnails are transparent PNGs whose aspect ratio rarely matches the
/// card exactly (and legacy thumbnails are often 16:10). Plain `BoxFit.cover`
/// crops important parts (sword tips, robot heads); plain `BoxFit.contain`
/// leaves the model small with heavy letterboxing.
///
/// This widget strikes the balance: the model is shown with `BoxFit.contain`
/// (never distorted, nothing important hard-cropped), centered over a premium
/// dark gradient, then lightly upscaled (default 1.12x, clipped to the card) so
/// it fills the card and reads as large/premium with minimal empty space.
/// Works for tall and wide models alike, and needs no re-upload of old assets.
class PremiumThumbnail extends StatelessWidget {
  /// A pre-configured image widget, e.g.
  /// `Image.network(url, fit: BoxFit.contain, alignment: Alignment.center, errorBuilder: ...)`.
  /// Keeping it a child preserves each call site's own error/loading builders.
  final Widget image;
  final bool isDark;
  final double scale;

  const PremiumThumbnail({
    super.key,
    required this.image,
    required this.isDark,
    this.scale = 1.12,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF1B1D29), Color(0xFF0E0F16)]
              : const [Color(0xFFF4F5F9), Color(0xFFE6E9F1)],
        ),
      ),
      // Clip the upscale so the enlarged model never spills outside the card.
      child: ClipRect(
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: image,
        ),
      ),
    );
  }
}
