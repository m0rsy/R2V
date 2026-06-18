// r2v_glass.dart
//
// Shared R2V "glass" design language used by the home screen and the freelance
// marketplace so they feel like one product. Contains:
//  - R2VBrand            : brand accent colors
//  - R2VAnimatedBackground : mesh-particle + gradient-blob background
//    (extracted verbatim from home_screen.dart so both screens share one source)
//  - R2VGlassCard        : blurred glass panel
//  - R2VSectionHeader    : title + subtitle section heading
//  - R2VEmptyState       : professional glass empty-state with icon + CTAs
//  - R2VGlassTopNav      : rounded glass pill top navigation (web/tablet)
//  - R2VGlassBottomNav   : rounded glass bottom navigation (mobile)

import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'r2v_section_nav.dart'; // shared LumaBar glass bottom nav
import 'r2v_notification_bell.dart'; // premium notification bell + popover

class R2VBrand {
  R2VBrand._();
  static const Color purple = Color(0xFF8A4FFF);
  static const Color lilac = Color(0xFFBC70FF);
  static const Color pink = Color(0xFFF72585);
  static const Color blue = Color(0xFF4895EF);
  static const Color cyan = Color(0xFF4CC9F0);
  static const Color bgDark = Color(0xFF0C0414);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color ink = Color(0xFF1E293B);
}

// ════════════════════════════════════════════════════════════════════
// Animated background (mesh particles + react-style gradient blobs)
// ════════════════════════════════════════════════════════════════════

class R2VAnimatedBackground extends StatelessWidget {
  final bool isDark;
  const R2VAnimatedBackground({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: MeshyParticleBackground(isDark: isDark)),
        Positioned.fill(child: _ReactHeroBackground(isDark: isDark)),
      ],
    );
  }
}

class _ReactHeroBackground extends StatelessWidget {
  final bool isDark;
  const _ReactHeroBackground({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Stack(
          children: [
            Positioned(
              top: -150,
              right: -50,
              child: Transform.rotate(
                angle: -0.35,
                child: Row(
                  children: [
                    _GradientBlob(isDark: isDark),
                    const SizedBox(width: 50),
                    _GradientBlob(isDark: isDark),
                    const SizedBox(width: 50),
                    _GradientBlob(isDark: isDark),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -50,
              right: -150,
              child: Transform.rotate(
                angle: -0.35,
                child: Row(
                  children: [
                    _GradientBlob(isDark: isDark),
                    const SizedBox(width: 50),
                    _GradientBlob(isDark: isDark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientBlob extends StatelessWidget {
  final bool isDark;
  const _GradientBlob({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Transform(
      transform: Matrix4.skewY(-0.7),
      child: Container(
        width: 140,
        height: 400,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [Colors.white.withOpacity(0.15), Colors.blue.shade300.withOpacity(0.35)]
                : [R2VBrand.lilac.withOpacity(0.25), R2VBrand.blue.withOpacity(0.25)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
    );
  }
}

class MeshyParticleBackground extends StatelessWidget {
  final bool isDark;
  const MeshyParticleBackground({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: _MeshyBgCore(isDark: isDark));
  }
}

class _MeshyBgCore extends StatefulWidget {
  final bool isDark;
  const _MeshyBgCore({required this.isDark});

  @override
  State<_MeshyBgCore> createState() => _MeshyBgCoreState();
}

class _MeshyBgCoreState extends State<_MeshyBgCore> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _rng = Random(42);

  Size _size = Size.zero;
  Offset _mouse = Offset.zero;
  bool _hasMouse = false;

  late List<_Particle> _ps;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ps = <_Particle>[];
    _ticker = createTicker((elapsed) {
      _t = elapsed.inMilliseconds / 1000.0;
      if (!mounted) return;
      if (_size == Size.zero) return;

      const dt = 1 / 60;
      for (final p in _ps) {
        p.pos = p.pos + p.vel * dt;
        if (p.pos.dx < 0 || p.pos.dx > _size.width) p.vel = Offset(-p.vel.dx, p.vel.dy);
        if (p.pos.dy < 0 || p.pos.dy > _size.height) p.vel = Offset(p.vel.dx, -p.vel.dy);
        p.pos = Offset(p.pos.dx.clamp(0.0, _size.width), p.pos.dy.clamp(0.0, _size.height));
      }
      setState(() {});
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _ensureParticles(Size s) {
    if (s == Size.zero) return;

    final area = s.width * s.height;
    int target = (area / 18000).round();
    target = target.clamp(35, 95);

    if (_ps.length == target) return;

    _ps = List.generate(target, (i) {
      final pos = Offset(_rng.nextDouble() * s.width, _rng.nextDouble() * s.height);
      final speed = 8 + _rng.nextDouble() * 18;
      final ang = _rng.nextDouble() * pi * 2;
      final vel = Offset(cos(ang), sin(ang)) * speed;
      final r = 1.2 + _rng.nextDouble() * 1.9;
      return _Particle(pos: pos, vel: vel, radius: r);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final s = Size(c.maxWidth, c.maxHeight);
      if (_size != s) {
        _size = s;
        _ensureParticles(s);
      }

      return MouseRegion(
        onHover: (e) {
          _hasMouse = true;
          _mouse = e.localPosition;
        },
        onExit: (_) => _hasMouse = false,
        child: CustomPaint(
          painter: _MeshPainter(
            particles: _ps,
            time: _t,
            size: s,
            mouse: _mouse,
            hasMouse: _hasMouse,
            isDark: widget.isDark,
          ),
        ),
      );
    });
  }
}

class _Particle {
  Offset pos;
  Offset vel;
  final double radius;

  _Particle({required this.pos, required this.vel, required this.radius});
}

class _MeshPainter extends CustomPainter {
  final List<_Particle> particles;
  final double time;
  final Size size;
  final Offset mouse;
  final bool hasMouse;
  final bool isDark;

  _MeshPainter({
    required this.particles,
    required this.time,
    required this.size,
    required this.mouse,
    required this.hasMouse,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size _) {
    final rect = Offset.zero & size;

    final bgColors = isDark
        ? const [Color(0xFF0F1118), Color(0xFF141625), Color(0xFF0B0D14)]
        : const [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFE2E8F0)];

    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: bgColors,
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    void glowBlob(Offset c, double r, Color col, double a) {
      final p = Paint()
        ..color = col.withOpacity(a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);
      canvas.drawCircle(c, r, p);
    }

    final center = Offset(size.width * 0.55, size.height * 0.35);
    final wobble = Offset(sin(time * 0.5) * 40, cos(time * 0.45) * 30);

    glowBlob(center + wobble, 280, isDark ? const Color(0xFF8A4FFF) : const Color(0xFFA855F7), isDark ? 0.18 : 0.12);
    glowBlob(
      Offset(size.width * 0.25, size.height * 0.70) + Offset(cos(time * 0.35) * 35, sin(time * 0.32) * 28),
      240,
      isDark ? const Color(0xFF4895EF) : const Color(0xFF38BDF8),
      isDark ? 0.14 : 0.10,
    );

    Offset parallax = Offset.zero;
    if (hasMouse) {
      final dx = (mouse.dx / max(1.0, size.width) - 0.5) * 18;
      final dy = (mouse.dy / max(1.0, size.height) - 0.5) * 18;
      parallax = Offset(dx, dy);
    }

    final connectDist = min(size.width, size.height) * 0.15;
    final connectDist2 = connectDist * connectDist;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < particles.length; i++) {
      final a = particles[i];
      final ap = a.pos + parallax * 0.25;

      for (int j = i + 1; j < particles.length; j++) {
        final b = particles[j];
        final bp = b.pos + parallax * 0.25;

        final dx = ap.dx - bp.dx;
        final dy = ap.dy - bp.dy;
        final d2 = dx * dx + dy * dy;

        if (d2 < connectDist2) {
          final t = 1.0 - (sqrt(d2) / connectDist);
          linePaint.color = isDark
              ? Colors.white.withOpacity(0.06 * t)
              : const Color(0xFF8A4FFF).withOpacity(0.15 * t);
          canvas.drawLine(ap, bp, linePaint);
        }
      }
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final pos = p.pos + parallax * 0.6;
      dotPaint.color = isDark ? Colors.white.withOpacity(0.12) : const Color(0xFF8A4FFF).withOpacity(0.25);
      canvas.drawCircle(pos, p.radius, dotPaint);
    }

    // Vignette: darken only the TOP edge (status bar / header legibility) and
    // fade to fully transparent before mid-screen. The BOTTOM is left clear so
    // the live animated particle background shows through behind the floating
    // LumaBar — otherwise the radial vignette darkened the bottom edge and read
    // as a dark strip behind the nav on the Talent screens.
    final vignette = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [Colors.black.withOpacity(0.38), Colors.transparent]
            : [Colors.white.withOpacity(0.32), Colors.transparent],
        stops: const [0.0, 0.45],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) => true;
}

// ════════════════════════════════════════════════════════════════════
// Glass primitives
// ════════════════════════════════════════════════════════════════════

/// A blurred glass panel matching the home screen's card style.
class R2VGlassCard extends StatefulWidget {
  const R2VGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.hoverLift = false,
    this.borderColor,
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool hoverLift;
  final Color? borderColor;
  final Color? fill;

  @override
  State<R2VGlassCard> createState() => _R2VGlassCardState();
}

class _R2VGlassCardState extends State<R2VGlassCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final lift = widget.hoverLift && _hover && isWeb;

    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      transform: Matrix4.identity()..translate(0.0, lift ? -5.0 : 0.0),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.fill ??
            (isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: widget.borderColor ??
              (_hover
                  ? (isDark ? Colors.white.withOpacity(0.22) : Colors.black.withOpacity(0.10))
                  : (isDark ? Colors.white.withOpacity(0.12) : Colors.white)),
        ),
        boxShadow: [
          if (isDark)
            BoxShadow(
              blurRadius: lift ? 24 : 18,
              color: Colors.black.withOpacity(lift ? 0.45 : 0.30),
              offset: const Offset(0, 12),
            )
          else
            BoxShadow(
              blurRadius: lift ? 16 : 10,
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: widget.child,
    );

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: panel,
      ),
    );

    if (widget.onTap != null) {
      content = MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: widget.onTap, child: content),
      );
    }
    return content;
  }
}

class R2VSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const R2VSectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: isDark ? Colors.white : R2VBrand.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    style: TextStyle(
                        color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54,
                        fontSize: 13)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Professional empty-state rendered as a glass card with a gradient icon
/// circle, title, explanation and up to two CTAs.
class R2VEmptyState extends StatelessWidget {
  const R2VEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.accent = R2VBrand.purple,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Color accent;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: R2VGlassCard(
            padding: const EdgeInsets.all(28),
            radius: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [accent, R2VBrand.pink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.4),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white : R2VBrand.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white.withOpacity(0.72) : Colors.black54,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
                if (primaryLabel != null || secondaryLabel != null) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      if (primaryLabel != null)
                        ElevatedButton(
                          onPressed: onPrimary,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? accent.withOpacity(0.22) : accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            side: isDark ? BorderSide(color: accent.withOpacity(0.55)) : BorderSide.none,
                          ),
                          child: Text(primaryLabel!, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      if (secondaryLabel != null)
                        OutlinedButton(
                          onPressed: onSecondary,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.white : R2VBrand.ink,
                            side: BorderSide(
                                color: isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.1)),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(secondaryLabel!, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Navigation
// ════════════════════════════════════════════════════════════════════

class R2VNavItem {
  final String label;
  final IconData icon;
  const R2VNavItem(this.label, this.icon);
}

/// Rounded glass pill top navigation matching the home screen's web top bar.
class R2VGlassTopNav extends StatefulWidget {
  const R2VGlassTopNav({
    super.key,
    required this.brand,
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    this.onBack,
    this.onProfile,
  });

  final String brand;
  final List<R2VNavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onBack;
  final VoidCallback? onProfile;

  @override
  State<R2VGlassTopNav> createState() => _R2VGlassTopNavState();
}

class _R2VGlassTopNavState extends State<R2VGlassTopNav> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9)),
            boxShadow: isDark
                ? []
                : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(
            children: [
              if (widget.onBack != null)
                _circleIcon(Icons.arrow_back_rounded, isDark, widget.onBack!),
              if (widget.onBack != null) const SizedBox(width: 8),
              const Icon(Icons.auto_awesome_rounded, size: 24, color: R2VBrand.lilac),
              const SizedBox(width: 8),
              Text(
                widget.brand,
                style: TextStyle(
                  color: isDark ? Colors.white : R2VBrand.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _tabs(isDark),
                ),
              ),
              const SizedBox(width: 14),
              // Notification bell sits just before the profile button, matching
              // the per-screen desktop top bars (Home, AI Studio, Marketplace…).
              R2VNotificationBell(isDark: isDark, size: 36),
              if (widget.onProfile != null) const SizedBox(width: 10),
              if (widget.onProfile != null)
                _circleIcon(Icons.person, isDark, widget.onProfile!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleIcon(IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isDark ? Colors.white : R2VBrand.ink, size: 19),
      ),
    );
  }

  Widget _tabs(bool isDark) {
    final n = widget.items.length;
    return LayoutBuilder(builder: (context, c) {
      final segW = c.maxWidth / n;
      const indW = 48.0;
      final underline = (_hover ?? widget.activeIndex).clamp(0, n - 1);
      final left = underline * segW + (segW - indW) / 2;

      return SizedBox(
        // 46px row so each tab has a comfortable 44–48px vertical hit area.
        height: 46,
        child: Stack(
          children: [
            Row(
              children: List.generate(n, (i) {
                final active = widget.activeIndex == i || _hover == i;
                return MouseRegion(
                  onEnter: (_) => setState(() => _hover = i),
                  onExit: (_) => setState(() => _hover = null),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    // Opaque so the whole segment is clickable, not just the text.
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onSelect(i),
                    child: SizedBox(
                      width: segW,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 120),
                          style: TextStyle(
                            color: active
                                ? (isDark ? Colors.white : R2VBrand.ink)
                                : (isDark ? Colors.white.withOpacity(0.7) : Colors.black54),
                            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                            fontSize: 13.5,
                          ),
                          child: Text(widget.items[i].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              left: left,
              bottom: 0,
              child: Container(
                width: indW,
                height: 2,
                decoration: BoxDecoration(
                  color: R2VBrand.lilac,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Rounded glass bottom navigation matching the home screen's mobile bar.
class R2VGlassBottomNav extends StatelessWidget {
  const R2VGlassBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<R2VNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // Render through the shared glassmorphic "LumaBar" so the talent/freelance
    // bottom nav matches the rest of the app. This widget keeps its own
    // R2VNavItem list + route navigation; LumaBar owns the visual + glow.
    return LumaBar(
      items: [
        for (final it in items) LumaBarItem(it.icon, it.label),
      ],
      currentIndex: currentIndex.clamp(0, items.length - 1),
      onTap: onTap,
    );
  }
}
