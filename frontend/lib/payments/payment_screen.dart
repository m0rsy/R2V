// lib/payments/payment_screen.dart
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/marketplace_service.dart';
import '../api/r2v_api.dart';
import '../api/api_exception.dart';

class PaymentScreen extends StatefulWidget {
  final MarketplaceAsset asset;

  const PaymentScreen({super.key, required this.asset});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int _methodIndex = 0;
  bool _loading = false;

  bool get _isWeb => MediaQuery.of(context).size.width >= 900;

  double _priceValue() {
    return widget.asset.price.toDouble();
  }

  bool _isFree() => _priceValue() <= 0.0;

  String _priceLabel() {
    final p = _priceValue();
    if (p <= 0.0) return "FREE";
    final asInt = p == p.roundToDouble();
    return asInt ? "EGP ${p.toInt()}" : "EGP ${p.toStringAsFixed(2)}";
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.asset.title.isNotEmpty ? widget.asset.title : "Checkout";
    final author = widget.asset.author;
    final poster = widget.asset.thumbUrl ?? "";
    final tag = widget.asset.category;
    final style = widget.asset.style;

    final priceText = _priceLabel();
    final free = _isFree();

    final maxW = _isWeb ? 980.0 : double.infinity;

    return Stack(
      children: [
        const Positioned.fill(child: _NebulaMeshBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text("Checkout", style: TextStyle(fontWeight: FontWeight.w700)),
            centerTitle: false,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: Column(
                        children: [
                          // ---------------------------
                          // Top summary area
                          // ---------------------------
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Poster thumb
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: _isWeb ? 140 : 110,
                                    height: _isWeb ? 100 : 86,
                                    color: Colors.white.withOpacity(0.06),
                                    child: poster.isEmpty
                                        ? Icon(Icons.image, color: Colors.white.withOpacity(0.35))
                                        : Image.network(
                                            poster,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.image_not_supported_rounded,
                                              color: Colors.white.withOpacity(0.35),
                                            ),
                                          ),
                                  ),
                                ),

                                const SizedBox(width: 14),

                                // Title + badges
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        author.isEmpty ? "" : "by $author",
                                        style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 12),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (tag.isNotEmpty) _MiniBadge(text: tag, accent: const Color(0xFF4CC9F0)),
                                          if (style.isNotEmpty) _MiniBadge(text: style, accent: const Color(0xFFBC70FF)),
                                          _MiniBadge(
                                            text: priceText,
                                            accent: free ? const Color(0xFF22C55E) : const Color(0xFF8A4FFF),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Total (right)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("Total", style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Text(
                                      priceText,
                                      style: TextStyle(
                                        color: free ? const Color(0xFF22C55E) : Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          Divider(color: Colors.white.withOpacity(0.10), height: 1),

                          // ---------------------------
                          // Content (methods)
                          // ---------------------------
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    free ? "This item is free" : "Choose payment method",
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.95),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  if (free)
                                    _GlassInfo(
                                      icon: Icons.download_rounded,
                                      title: "FREE Download",
                                      subtitle: "No payment required. Tap Download below.",
                                    )
                                  else
                                    Column(
                                      children: [
                                        _MethodTile(
                                          selected: _methodIndex == 0,
                                          icon: Icons.credit_card_rounded,
                                          title: "Card",
                                          subtitle: "Visa / MasterCard",
                                          onTap: () => setState(() => _methodIndex = 0),
                                        ),
                                        const SizedBox(height: 10),
                                        _MethodTile(
                                          selected: _methodIndex == 1,
                                          icon: Icons.account_balance_wallet_rounded,
                                          title: "Wallet",
                                          subtitle: "Mobile wallet / balance",
                                          onTap: () => setState(() => _methodIndex = 1),
                                        ),
                                        const SizedBox(height: 10),
                                        _MethodTile(
                                          selected: _methodIndex == 2,
                                          icon: Icons.account_balance_rounded,
                                          title: "Bank Transfer",
                                          subtitle: "Manual transfer (UI only)",
                                          onTap: () => setState(() => _methodIndex = 2),
                                        ),
                                      ],
                                    ),

                                  const SizedBox(height: 16),

                                ],
                              ),
                            ),
                          ),

                          // ---------------------------
                          // Bottom action bar
                          // ---------------------------
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    label: const Text("Cancel"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(color: Colors.white.withOpacity(0.18)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _loading
                                        ? null
                                        : () async {
                                            setState(() => _loading = true);
                                            try {
                                              if (free) {
                                                final url = await r2vMarketplace.downloadAsset(widget.asset.id);
                                                if (url.isEmpty) {
                                                  throw Exception('Missing download url');
                                                }
                                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                              } else {
                                                final url = await r2vMarketplace.checkoutAsset(widget.asset.id);
                                                if (url.isEmpty) {
                                                  throw Exception('Missing checkout url');
                                                }
                                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                              }
                                            } on ApiException catch (e) {
                                              _toast(e.message);
                                            } catch (_) {
                                              _toast("Checkout failed");
                                            } finally {
                                              if (mounted) setState(() => _loading = false);
                                            }
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: free ? const Color(0xFF22C55E) : const Color(0xFF8A4FFF),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: Text(
                                      free ? "Download" : "Pay $priceText",
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// UI components
// ============================================================

class _MethodTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MethodTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(selected ? 0.30 : 0.20),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFBC70FF).withOpacity(0.55) : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(selected ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Icon(icon, color: Colors.white.withOpacity(0.85), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? const Color(0xFFBC70FF) : Colors.white.withOpacity(0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassInfo extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _GlassInfo({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.85), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.72), height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String text;
  final Color accent;

  const _MiniBadge({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.40)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.92),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ============================================================
// Background: Nebula (same vibe as your marketplace)
// ============================================================

class _NebulaMeshBackground extends StatefulWidget {
  const _NebulaMeshBackground();

  @override
  State<_NebulaMeshBackground> createState() => _NebulaMeshBackgroundState();
}

class _NebulaMeshBackgroundState extends State<_NebulaMeshBackground> with SingleTickerProviderStateMixin {
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
    int target = (area / 18000).round().clamp(35, 95);

    if (_ps.length == target) return;

    _ps = List.generate(target, (i) {
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
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);
      canvas.drawCircle(c, r, p);
    }

    final center = Offset(size.width * 0.55, size.height * 0.35);
    final wobble = Offset(sin(time * 0.5) * 40, cos(time * 0.45) * 30);

    glowBlob(center + wobble, 280, const Color(0xFF8A4FFF), 0.18);
    glowBlob(
      Offset(size.width * 0.25, size.height * 0.70) + Offset(cos(time * 0.35) * 35, sin(time * 0.32) * 28),
      240,
      const Color(0xFF4895EF),
      0.14,
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
          linePaint.color = Colors.white.withOpacity(0.06 * t);
          canvas.drawLine(ap, bp, linePaint);
        }
      }
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final pos = p.pos + parallax * 0.6;
      dotPaint.color = Colors.white.withOpacity(0.12);
      canvas.drawCircle(pos, p.radius, dotPaint);
    }

    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.15,
        colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
        stops: const [0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _NebulaPainter oldDelegate) => true;
}
