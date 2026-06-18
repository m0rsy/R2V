import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Spacing scale (logical pixels). Use instead of magic numbers.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: 20);
  static const EdgeInsets card = EdgeInsets.all(16);
}

/// Corner radii.
class AppRadius {
  AppRadius._();

  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));
}

/// Standard elevations / shadows for cards and overlays.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 4)),
  ];

  static List<BoxShadow> glow(Color c) => [
    BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: -4),
  ];
}

/// A glass-style surface decoration matching the app's aesthetic.
BoxDecoration glassDecoration({
  double radius = AppRadius.md,
  Color? color,
  Color? borderColor,
}) {
  return BoxDecoration(
    color: color ?? AppColors.surfaceGlass,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? AppColors.border),
  );
}
