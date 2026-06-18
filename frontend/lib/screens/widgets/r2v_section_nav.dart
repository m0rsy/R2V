import 'dart:ui';
import 'package:flutter/material.dart';

/// A single destination rendered inside a [LumaBar].
class LumaBarItem {
  final IconData icon;
  final String label;
  const LumaBarItem(this.icon, this.label);
}

/// The futuristic floating "LumaBar" — a glassmorphic capsule that floats near
/// the bottom-center of the screen with icon-only buttons. The active item sits
/// on a glowing pink→purple→blue gradient circle that slides smoothly between
/// tabs; the active icon scales up, inactive icons are muted, and each item
/// shows a tooltip on hover / long-press.
///
/// This is the shared visual shell for every mobile bottom nav in the app. It
/// is fully data-driven via [items] and a single [onTap] callback, so callers
/// keep their own navigation logic (route push, internal tab switch, …) and
/// simply decide which index is [currentIndex]. Pass `currentIndex = -1` (or any
/// out-of-range value) to render with no highlighted tab.
///
/// Mount it via `Scaffold.bottomNavigationBar` with `extendBody: false` so the
/// Scaffold reserves the bar's full height (capsule + margins + safe area) and
/// page content is never hidden behind it. Other widgets (e.g. the floating
/// chat bubble) read [barFootprint] to stay clear of the bar.
class LumaBar extends StatelessWidget {
  const LumaBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<LumaBarItem> items;

  /// Index of the active destination, or out-of-range for "none active".
  final int currentIndex;

  /// Called with the tapped index. Callers decide whether tapping the active
  /// item is a no-op.
  final ValueChanged<int> onTap;

  /// Total vertical footprint reserved below page content (capsule height +
  /// bottom margin). Safe-area inset is added on top of this at runtime.
  static const double barFootprint = capsuleHeight + bottomMargin;
  static const double capsuleHeight = 76;
  static const double bottomMargin = 16;
  static const double _hMargin = 22;
  static const double _maxWidth = 440;
  static const double _glowSize = 52;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      // IMPORTANT: heightFactor: 1.0 shrink-wraps this Align to the capsule's
      // height. Without it (e.g. a plain Center), the bottomNavigationBar slot
      // hands down maxHeight == full screen height, the Align expands to fill
      // it, and the capsule renders at the vertical CENTER of the screen
      // instead of pinned to the bottom. Horizontal centering (for the 440-max
      // pill on wider phones) is preserved by the alignment.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_hMargin, 0, _hMargin, bottomMargin),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: _Capsule(
              height: capsuleHeight,
              child: LayoutBuilder(
                builder: (context, c) {
                  final segW = c.maxWidth / items.length;
                  const indicator = _glowSize;
                  final hasActive =
                      currentIndex >= 0 && currentIndex < items.length;
                  final left = currentIndex * segW + (segW - indicator) / 2;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glowing gradient pill that slides behind the active icon.
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        left: hasActive ? left : -indicator * 2,
                        top: (capsuleHeight - indicator) / 2,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: hasActive ? 1 : 0,
                          child: const _ActiveGlow(size: indicator),
                        ),
                      ),

                      // Icons on top.
                      Row(
                        children: List.generate(items.length, (i) {
                          return Expanded(
                            child: _LumaItem(
                              item: items[i],
                              active: i == currentIndex,
                              onTap: () => onTap(i),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Global mobile section navigation for R2V — a thin, route-based wrapper around
/// [LumaBar] that mirrors the desktop top-nav destinations (Home · AI · Market ·
/// Talent · Settings).
///
/// Desktop/tablet keeps the existing top nav — this widget is only mounted on
/// the mobile branch of each screen (width < 900). Routing uses
/// `pushReplacementNamed` against the canonical route names, so the active tab
/// stays correct after navigation, browser refresh, and deep links.
///
/// Pass [currentIndex] = -1 (or any out-of-range value) to render with no
/// highlighted tab (e.g. on secondary screens that aren't one of the five).
class R2VSectionNav extends StatelessWidget {
  const R2VSectionNav({super.key, required this.currentIndex});

  /// 0 = Home, 1 = AI, 2 = Scan, 3 = Market, 4 = Talent, 5 = Profile/Settings.
  final int currentIndex;

  /// See [LumaBar.barFootprint]. Re-exported here because other widgets (e.g.
  /// the floating chat bubble) already read it from this class.
  static const double barFootprint = LumaBar.barFootprint;

  /// THE single source of truth for the mobile nav. Every page (Home, AI, Scan,
  /// Market, Talent, Settings/Profile) renders this exact list — no page defines
  /// its own. Indices line up with [routes] and with Home's internal tabs.
  static const List<LumaBarItem> items = [
    LumaBarItem(Icons.home_rounded, 'Home'),
    LumaBarItem(Icons.bolt_rounded, 'AI'),
    LumaBarItem(Icons.photo_camera_rounded, 'Scan'),
    LumaBarItem(Icons.storefront_rounded, 'Market'),
    LumaBarItem(Icons.work_rounded, 'Talent'),
    LumaBarItem(Icons.person_rounded, 'Profile'),
  ];

  /// Canonical route for each item (index-aligned with [items]).
  static const List<String> routes = [
    '/home',
    '/aichat',
    '/photo_scan',
    '/explore',
    '/talent',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    return LumaBar(
      items: items,
      currentIndex: currentIndex,
      onTap: (i) {
        if (i == currentIndex) return; // already here — no-op
        Navigator.pushReplacementNamed(context, routes[i]);
      },
    );
  }
}

/// The frosted-glass capsule shell.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(height / 2);

    return DecoratedBox(
      // Outer soft glow/shadow sits OUTSIDE the clip so it isn't cut off.
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            blurRadius: 34,
            spreadRadius: -6,
            color: Colors.black.withOpacity(isDark ? 0.55 : 0.18),
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            blurRadius: 30,
            spreadRadius: -10,
            color: const Color(0xFF8A4FFF).withOpacity(isDark ? 0.28 : 0.16),
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                // Opaque dark "glass" base. The previous white@0.12/0.05 fill was
                // nearly transparent, so page content scrolling beneath the pill
                // was visible through the BackdropFilter (read as a "bar" behind
                // the nav). A navy/near-black base at ~0.88–0.92 hides content
                // completely while the blur + border + glow keep the glassy look.
                colors: isDark
                    ? [
                        const Color(0xFF18122E).withOpacity(0.88),
                        const Color(0xFF0A0716).withOpacity(0.92),
                      ]
                    : [
                        Colors.white.withOpacity(0.96),
                        Colors.white.withOpacity(0.90),
                      ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.16)
                    : Colors.white.withOpacity(0.9),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Glowing gradient indicator behind the active icon. Animates in with a gentle
/// scale + fade each time the bar mounts on a new screen.
class _ActiveGlow extends StatelessWidget {
  const _ActiveGlow({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // R2V tri-color: pink → purple → blue.
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF72585), Color(0xFF9B5CFF), Color(0xFF5B8DEF)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF72585).withOpacity(0.40),
              blurRadius: 20,
              spreadRadius: -1,
              offset: const Offset(-2, 2),
            ),
            BoxShadow(
              color: const Color(0xFF8A4FFF).withOpacity(0.55),
              blurRadius: 24,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: const Color(0xFF5B8DEF).withOpacity(0.38),
              blurRadius: 32,
              spreadRadius: -2,
              offset: const Offset(2, 6),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single tappable icon with hover/active scale and a tooltip label.
class _LumaItem extends StatefulWidget {
  const _LumaItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final LumaBarItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_LumaItem> createState() => _LumaItemState();
}

class _LumaItemState extends State<_LumaItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color idle =
        isDark ? Colors.white.withOpacity(0.60) : Colors.black54;
    // Active icon is white (it rides on the glowing gradient pill); hover lifts
    // an idle icon toward the brand lilac for feedback on web.
    final Color fg = widget.active
        ? Colors.white
        : (_hover ? const Color(0xFFBC70FF) : idle);
    final double scale = widget.active ? 1.30 : (_hover ? 1.12 : 1.0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.item.label,
        waitDuration: const Duration(milliseconds: 350),
        child: Semantics(
          label: widget.item.label,
          button: true,
          selected: widget.active,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                scale: scale,
                child: Icon(widget.item.icon, size: 25, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
