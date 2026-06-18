import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../api/r2v_api.dart';
import '../api/api_exception.dart';
import '../widgets/premium_auth_field.dart';

class OTPVerification extends StatefulWidget {
  final String email;

  const OTPVerification({super.key, required this.email});

  @override
  State<OTPVerification> createState() => _OTPVerificationState();
}

class _OTPVerificationState extends State<OTPVerification> {
  static const Color _accentPink = Color(0xFFF72585);
  static const Color _accentLavender = Color(0xFFBC70FF);
  static const Color _accentCyan = Color(0xFF4CC9F0);

  final List<TextEditingController> otp = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focus = List.generate(4, (_) => FocusNode());

  bool _loading = false;

  @override
  void dispose() {
    for (final c in otp) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _code => otp.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_loading) return;

    final code = _code;
    if (code.length != 4) {
      _error("Enter the full 4-digit code");
      return;
    }

    setState(() => _loading = true);
    try {
      final resetToken = await r2vPasswordReset.verifyCode(widget.email, code);
      if (!mounted) return;

      Navigator.pushNamed(context, "/setnewpass", arguments: resetToken);
    } on ApiException catch (e) {
      if (!mounted) return;
      _error(e.message);
    } catch (_) {
      if (!mounted) return;
      _error("Verification failed");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_loading) return;

    setState(() => _loading = true);
    try {
      final res = await r2vPasswordReset.requestReset(widget.email);
      if (!mounted) return;

      if (res.devCode != null && res.devCode!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification code: ${res.devCode}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification code resent')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _error(e.message);
    } catch (_) {
      if (!mounted) return;
      _error("Failed to resend code");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final contentWidth = w > 540 ? 540.0 : w;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: NebulaMeshBackground()),

          // ✅ Theme pill
          Positioned(
            left: 26,
            top: h * 0.03,
            child: _leftPill(),
          ),

          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
                physics: const BouncingScrollPhysics(),
                child: _glassCard(child: _content()),
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Verification",
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Enter the 4-digit code sent to:",
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.email,
          style: const TextStyle(
            color: _accentCyan,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 18),

        Center(
          child: Wrap(
            spacing: 12,
            children: List.generate(4, (i) => _otpBox(i)),
          ),
        ),

        const SizedBox(height: 18),

        GestureDetector(
          onTap: _loading ? null : _verify,
          child: Opacity(
            opacity: _loading ? 0.75 : 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [_accentPink, _accentLavender],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 22,
                    color: _accentLavender.withOpacity(0.18),
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        "Verify Code",
                        style: TextStyle(
                          fontSize: 16.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Center(
          child: TextButton(
            onPressed: _loading ? null : _resend,
            child: const Text(
              "Resend Code",
              style: TextStyle(
                color: _accentCyan,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _otpBox(int index) {
    return PremiumOtpBox(
      controller: otp[index],
      focusNode: _focus[index],
      onChanged: (v) {
        if (v.isNotEmpty) {
          if (index < 3) {
            _focus[index + 1].requestFocus();
          } else {
            FocusScope.of(context).unfocus();
            // Nice UX: auto verify when last digit entered
            _verify();
          }
        } else {
          // backspace UX: go back
          if (index > 0) _focus[index - 1].requestFocus();
        }
      },
    );
  }
}

// =====================================================================
// ✅ Nebula background (mouse hover parallax) — same theme
// =====================================================================

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
        if (p.pos.dx < 0 || p.pos.dx > _size.width) p.vel = Offset(-p.vel.dx, p.vel.dy);
        if (p.pos.dy < 0 || p.pos.dy > _size.height) p.vel = Offset(p.vel.dx, -p.vel.dy);
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
