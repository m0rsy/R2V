import 'package:flutter/material.dart';

/// Central R2V color palette.
///
/// Single source of truth for brand colors, surfaces, text and status colors.
/// Prefer referencing these constants instead of inlining `Color(0x...)`
/// literals so the UI stays visually consistent.
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────────
  static const Color brandPurple = Color(0xFFBC70FF);
  static const Color brandCyan = Color(0xFF4CC9F0);
  static const Color brandPink = Color(0xFFF72585);

  /// Primary brand gradient (purple → cyan), used for hero/CTA accents.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandPurple, brandCyan],
  );

  // ── Dark surfaces (default theme) ──────────────────────────────────
  static const Color bg = Color(0xFF0D0E13);
  static const Color surface = Color(0xFF15171F);
  static const Color surfaceHigh = Color(0xFF1C1F29);
  static const Color surfaceGlass = Color(0x59000000); // black @ 0.35

  // ── Borders / dividers ─────────────────────────────────────────────
  static const Color border = Color(0x1FFFFFFF); // white @ 0.12
  static const Color borderStrong = Color(0x33FFFFFF); // white @ 0.20

  // ── Text ───────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xB3FFFFFF); // white @ 0.70
  static const Color textMuted = Color(0x80FFFFFF); // white @ 0.50

  // ── Light theme surfaces ───────────────────────────────────────────
  static const Color lightBg = Color(0xFFF5F7FA);
  static const Color lightSurface = Colors.white;
  static const Color lightTextPrimary = Color(0xFF1A1B20);
  static const Color lightTextSecondary = Color(0x99000000);

  // ── Semantic ───────────────────────────────────────────────────────
  static const Color success = Color(0xFF1FA463);
  static const Color info = Color(0xFF2D8CFF);
  static const Color warning = Color(0xFFE07B00);
  static const Color danger = Color(0xFFD93636);
  static const Color star = Color(0xFFF5B301);

  /// Status colors shared by orders / projects / proposals / payments.
  static const Map<String, Color> status = {
    // orders
    'pending': Color(0xFF9AA0A6),
    'active': info,
    'submitted': Color(0xFFB58A00),
    'revision_requested': warning,
    'completed': success,
    'cancelled': Color(0xFF8A8A8A),
    'disputed': danger,
    // projects
    'open': success,
    'in_progress': info,
    // proposals
    'accepted': success,
    'rejected': danger,
    'withdrawn': Color(0xFF8A8A8A),
    // applications
    'approved': success,
    'needs_info': warning,
    // payments
    'unpaid': Color(0xFF9AA0A6),
    'funded': info,
    'released': success,
    'refunded': warning,
  };

  static Color statusColor(String key, Color fallback) =>
      status[key] ?? fallback;
}
