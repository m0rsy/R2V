import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:page_transition/page_transition.dart';
import 'package:video_player/video_player.dart';

import 'signin.dart';

class Welcome extends StatefulWidget {
  const Welcome({super.key});

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  Timer? _timer;

  late final VideoPlayerController _vc;
  bool _videoReady = false;
  bool _videoFailed = false;

  // ✅ Tweak these
  final double videoRadius = 26;          // video corner roundness
  final double videoBoxAspect = 0.8;      // 1.0 = square, 4/5 = taller, 16/9 = wider
  final bool cropToFill = true;           // true = BoxFit.cover (cropped), false = contain (no crop)

  @override
  void initState() {
    super.initState();

    _vc = VideoPlayerController.asset("assets/videos/loading.mp4")
      ..setLooping(true)
      ..setVolume(0);

    _vc.initialize().then((_) {
      if (!mounted) return;
      setState(() => _videoReady = true);
      _vc.play();
    }).catchError((error) {
      if (!mounted) return;
      setState(() => _videoFailed = true);
      debugPrint("Welcome video failed to load: $error");
    });

    _timer = Timer(const Duration(seconds:8), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageTransition(type: PageTransitionType.fade, child: SignIn()),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _vc.dispose();
    super.dispose();
  }

  // ✅ Same "R2V" pill as the other pages
  Widget _leftPill() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFFBC70FF), size: 18),
              SizedBox(width: 8),
              Text(
                "R2V",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final contentWidth = w > 520 ? 520.0 : w;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: NebulaMeshBackground()),

          // ✅ Top-left pill
          Positioned(
            left: 26,
            top: h * 0.03,
            child: _leftPill(),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: _glassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ Rounded MP4 box with controllable aspect ratio
                        ClipRRect(
                          borderRadius: BorderRadius.circular(videoRadius),
                          child: AspectRatio(
                            aspectRatio: videoBoxAspect,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // background behind video to avoid white corners
                                Container(color: Colors.black.withOpacity(0.18)),

                                if (_videoReady)
                                  FittedBox(
                                    fit: cropToFill ? BoxFit.cover : BoxFit.contain,
                                    child: SizedBox(
                                      width: _vc.value.size.width,
                                      height: _vc.value.size.height,
                                      child: VideoPlayer(_vc),
                                    ),
                                  )
                                else if (_videoFailed)
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Image.asset(
                                      "assets/R2Vlogo.png",
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                else
                                  const Center(child: CircularProgressIndicator()),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),
                        Text(
                          "Loading…",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Preparing your studio",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.22),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                blurRadius: 40,
                color: Colors.black.withOpacity(0.45),
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/* -----------------------------------------------------------------------
   NebulaMeshBackground (same theme background with mouse parallax)
------------------------------------------------------------------------ */

class NebulaMeshBackground extends StatefulWidget {
  const NebulaMeshBackground({super.key});

  @override
  State<NebulaMeshBackground> createState() => _NebulaMeshBackgroundState();
}

class _NebulaMeshBackgroundState extends State<NebulaMeshBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _rng = Random(42);

  Size _size = Size.zero;
  Offset _mouse = Offset.zero;
  bool _hasMouse = false;

  late List<_NebulaParticle> _ps;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ps = <_NebulaParticle>[];
    _ticker = createTicker((elapsed) {
      _t = elapsed.inMilliseconds / 1000.0;
      if (!mounted) return;
      if (_size == Size.zero) return;

      const dt = 1 / 60;
      for (final p in _ps) {
        p.pos = p.pos + p.vel * dt;
        if (p.pos.dx < 0 || p.pos.dx > _size.width) {
          p.vel = Offset(-p.vel.dx, p.vel.dy);
        }
        if (p.pos.dy < 0 || p.pos.dy > _size.height) {
          p.vel = Offset(p.vel.dx, -p.vel.dy);
        }
        p.pos = Offset(
          p.pos.dx.clamp(0.0, _size.width),
          p.pos.dy.clamp(0.0, _size.height),
        );
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

    _ps = List.generate(target, (_) {
      final pos = Offset(_rng.nextDouble() * s.width, _rng.nextDouble() * s.height);
      final speed = 8 + _rng.nextDouble() * 18;
      final ang = _rng.nextDouble() * pi * 2;
      final vel = Offset(cos(ang), sin(ang)) * speed;
      final r = 1.2 + _rng.nextDouble() * 1.9;
      return _NebulaParticle(pos: pos, vel: vel, radius: r);
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
          painter: _NebulaPainter(
            particles: _ps,
            time: _t,
            size: s,
            mouse: _mouse,
            hasMouse: _hasMouse,
          ),
        ),
      );
    });
  }
}

class _NebulaParticle {
  Offset pos;
  Offset vel;
  final double radius;

  _NebulaParticle({required this.pos, required this.vel, required this.radius});
}

class _NebulaPainter extends CustomPainter {
  final List<_NebulaParticle> particles;
  final double time;
  final Size size;

  final Offset mouse;
  final bool hasMouse;

  _NebulaPainter({
    required this.particles,
    required this.time,
    required this.size,
    required this.mouse,
    required this.hasMouse,
  });

  @override
  void paint(Canvas canvas, Size _) {
    final rect = Offset.zero & size;

    Offset parallax = Offset.zero;
    if (hasMouse) {
      final dx = (mouse.dx / max(1.0, size.width) - 0.5) * 18;
      final dy = (mouse.dy / max(1.0, size.height) - 0.5) * 18;
      parallax = Offset(dx, dy);
    }

    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F1118), Color(0xFF141625), Color(0xFF0B0D14)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    void glowBlob(Offset c, double r, Color col, double a) {
      final p = Paint()
        ..color = col.withOpacity(a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 110);
      canvas.drawCircle(c, r, p);
    }

    final wobble = Offset(sin(time * 0.5) * 40, cos(time * 0.45) * 30);

    glowBlob(
      Offset(size.width * 0.60, size.height * 0.20) + wobble + parallax * 0.35,
      360,
      const Color(0xFF8A4FFF),
      0.20,
    );

    glowBlob(
      Offset(size.width * 0.20, size.height * 0.72) +
          Offset(cos(time * 0.35) * 35, sin(time * 0.32) * 28) +
          parallax * 0.25,
      240,
      const Color(0xFF4895EF),
      0.12,
    );

    final connectDist = min(size.width, size.height) * 0.16;
    final connectDist2 = connectDist * connectDist;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < particles.length; i++) {
      final a = particles[i].pos + parallax * 0.25;

      for (int j = i + 1; j < particles.length; j++) {
        final b = particles[j].pos + parallax * 0.25;

        final dx = a.dx - b.dx;
        final dy = a.dy - b.dy;
        final d2 = dx * dx + dy * dy;

        if (d2 < connectDist2) {
          final t = 1.0 - (sqrt(d2) / connectDist);
          linePaint.color = Colors.white.withOpacity(0.055 * t);
          canvas.drawLine(a, b, linePaint);
        }
      }
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      dotPaint.color = Colors.white.withOpacity(0.12);
      final pos = p.pos + parallax * 0.55;
      canvas.drawCircle(pos, p.radius, dotPaint);
    }

    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.15,
        colors: [Colors.transparent, Colors.black.withOpacity(0.60)],
        stops: const [0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _NebulaPainter oldDelegate) => true;
}
