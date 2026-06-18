import 'dart:ui';

import 'package:flutter/material.dart';

/// Premium, glassmorphism progress card shown in the AI page while a 3D model
/// is being generated. It replaces the old "Typing..." bubble with a live,
/// segmented progress bar driven by the backend's Modal pipeline fields
/// (progress / stage / message).
///
/// Drop-in usage:
/// ```dart
/// AiGenerationProgressCard(
///   progress: job.progress,
///   stage: job.stage,
///   message: job.message,
///   withTexture: message.withTexture,
///   status: job.status,
///   isDark: isDark,
/// )
/// ```
class AiGenerationProgressCard extends StatelessWidget {
  /// Raw progress 0–100 as reported by the backend.
  final int progress;

  /// Modal pipeline stage key (e.g. `texturing`, `image_to_mesh`).
  final String? stage;

  /// Human status line from Modal (e.g. "Applying official PBR texture...").
  final String? message;

  /// Whether the user requested a textured model. Drives the title and hides
  /// the texturing stage when false.
  final bool? withTexture;

  /// Normalized job status (`queued` / `running` / `failed` / ...).
  final String? status;

  final bool isDark;

  const AiGenerationProgressCard({
    super.key,
    required this.progress,
    required this.isDark,
    this.stage,
    this.message,
    this.withTexture,
    this.status,
  });

  static const Color _primary = Color(0xFF8A4FFF);
  static const Color _accent = Color(0xFFBC70FF);

  // ----- Stage label + fallback progress mapping --------------------------

  /// Maps a Modal stage key to a friendly label.
  static String stageLabel(String? stage, {bool withTexture = true}) {
    switch ((stage ?? '').toLowerCase()) {
      case 'queued':
        return 'Queued for generation';
      case 'starting':
      case 'preparing':
        return 'Preparing AI pipeline';
      case 'text_to_image':
        return 'Generating reference image';
      case 'image_ready':
        return 'Reference image generated';
      case 'background_removal':
        return 'Cleaning background';
      case 'image_to_mesh':
        return 'Creating 3D mesh';
      case 'mesh_ready':
        return '3D mesh created';
      case 'texturing':
        // Texturing should never surface when texture is disabled.
        return withTexture
            ? 'Applying official PBR texture'
            : 'Refining 3D mesh';
      case 'finalizing':
        return 'Finalizing 3D model';
      case 'done':
      case 'succeeded':
        return '3D model ready';
      case 'failed':
        return 'Generation failed';
      default:
        return withTexture
            ? 'Generating textured 3D model'
            : 'Generating 3D mesh';
    }
  }

  /// Title line for the card, based on the requested texture mode.
  static String titleFor({bool? withTexture}) => withTexture == false
      ? 'Generating 3D mesh'
      : 'Generating textured 3D model';

  /// Stage-based progress fallback used when the numeric value is missing.
  static const Map<String, int> _stageProgress = {
    'queued': 0,
    'starting': 5,
    'preparing': 5,
    'text_to_image': 15,
    'image_ready': 30,
    'background_removal': 35,
    'image_to_mesh': 45,
    'mesh_ready': 65,
    'texturing': 75,
    'finalizing': 95,
    'done': 100,
    'succeeded': 100,
  };

  /// Resolves an effective 0–100 progress, falling back to the stage when the
  /// backend did not provide a numeric value.
  static int resolveProgress(int? progress, String? stage) {
    if (progress != null && progress > 0) return progress.clamp(0, 100);
    final fromStage = _stageProgress[(stage ?? '').toLowerCase()];
    if (fromStage != null) return fromStage;
    return progress?.clamp(0, 100) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final bool textured = withTexture != false;
    final int value = resolveProgress(progress, stage);
    final String title = titleFor(withTexture: withTexture);
    final String label = stageLabel(stage, withTexture: textured);
    // Subtitle: prefer Modal's message, otherwise the friendly stage label.
    final String subtitle = (message != null && message!.trim().isNotEmpty)
        ? message!.trim()
        : label;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        _primary.withOpacity(0.18),
                        Colors.white.withOpacity(0.04),
                      ]
                    : [
                        _primary.withOpacity(0.12),
                        Colors.white.withOpacity(0.55),
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _accent.withOpacity(isDark ? 0.35 : 0.30),
              ),
              boxShadow: [
                BoxShadow(
                  color: _primary.withOpacity(isDark ? 0.30 : 0.18),
                  blurRadius: 28,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header: icon + stage label (left) / percentage (right)
                Row(
                  children: [
                    _PulseIcon(isDark: isDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white.withOpacity(0.85)
                              : const Color(0xFF4C3A78),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _AnimatedPercent(value: value, isDark: isDark),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                // Subtitle / message
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withOpacity(0.62)
                        : Colors.black.withOpacity(0.55),
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                // Segmented animated progress bar
                SegmentedGenerationProgress(
                  progress: value,
                  isDark: isDark,
                  segments: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of rounded segments that fill smoothly from left to right based on a
/// 0–100 [progress] value. Filled segments use a premium primary/accent
/// gradient with a soft glow; unfilled segments stay muted and translucent.
class SegmentedGenerationProgress extends StatelessWidget {
  final int progress;
  final int segments;
  final bool isDark;

  const SegmentedGenerationProgress({
    super.key,
    required this.progress,
    required this.isDark,
    this.segments = 20,
  });

  @override
  Widget build(BuildContext context) {
    final double target = (progress.clamp(0, 100)) / 100.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        // How many segments (fractional) should be lit.
        final double lit = animated * segments;
        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = 5.0;
            final totalGap = gap * (segments - 1);
            final segW = (constraints.maxWidth - totalGap) / segments;
            return Row(
              children: List.generate(segments, (i) {
                // Fractional fill for this segment (0..1) — gives a smooth edge.
                final fill = (lit - i).clamp(0.0, 1.0);
                return Padding(
                  padding: EdgeInsets.only(right: i == segments - 1 ? 0 : gap),
                  child: _Segment(width: segW, fill: fill, isDark: isDark),
                );
              }),
            );
          },
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  final double width;
  final double fill; // 0..1
  final bool isDark;

  const _Segment({
    required this.width,
    required this.fill,
    required this.isDark,
  });

  static const Color _primary = Color(0xFF8A4FFF);
  static const Color _accent = Color(0xFFBC70FF);

  @override
  Widget build(BuildContext context) {
    final bool active = fill > 0.02;
    final Color base = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: active ? null : base,
        borderRadius: BorderRadius.circular(6),
        gradient: active
            ? LinearGradient(
                colors: [
                  Color.lerp(
                    _primary,
                    _accent,
                    0.0,
                  )!.withOpacity(0.35 + 0.65 * fill),
                  _accent.withOpacity(0.35 + 0.65 * fill),
                ],
              )
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: _accent.withOpacity(0.55 * fill),
                  blurRadius: 8,
                  spreadRadius: -1,
                ),
              ]
            : null,
        border: Border.all(
          color: active
              ? _accent.withOpacity(0.5 * fill)
              : (isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.04)),
        ),
      ),
    );
  }
}

/// Smoothly animated percentage number (e.g. 70%).
class _AnimatedPercent extends StatelessWidget {
  final int value;
  final bool isDark;

  const _AnimatedPercent({required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return Text(
          '${v.round()}%',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontSize: 15,
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

/// A gently pulsing "spark/generation" icon used in the card header.
class _PulseIcon extends StatefulWidget {
  final bool isDark;
  const _PulseIcon({required this.isDark});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  static const Color _primary = Color(0xFF8A4FFF);
  static const Color _accent = Color(0xFFBC70FF);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_primary, _accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.35 + 0.35 * t),
                blurRadius: 12 + 6 * t,
                spreadRadius: 1 * t,
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 17,
            color: Colors.white,
          ),
        );
      },
    );
  }
}
