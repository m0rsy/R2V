import 'package:flutter/material.dart';

/// Shared desktop top-navigation tab strip used by every desktop page
/// (Home · AI Studio · Marketplace · Find Talent · Settings), so the hitbox,
/// hover, underline and wrapping behaviour are identical everywhere instead of
/// being re-implemented per screen.
///
/// Key behaviours:
/// * The WHOLE tab segment is clickable — `HitTestBehavior.opaque` + a ~46px
///   tall row — not just the text glyphs.
/// * Labels never wrap (`softWrap: false`, `maxLines: 1`) — this is what stops
///   "Marketplace" breaking onto two lines.
/// * Web pointer cursor over the full segment, with hover/active text brighten
///   and an animated brand-purple underline.
/// * Self-contained navigation: tapping a tab `pushReplacementNamed`s its route
///   (no-op when it is already the active tab), matching the rest of the app.
class R2VTopNavTabs extends StatefulWidget {
  /// 0 = Home, 1 = AI Studio, 2 = Marketplace, 3 = Find Talent, 4 = Settings.
  /// Pass -1 (or any out-of-range value) to show no active highlight/underline.
  final int activeIndex;
  final bool isDark;

  const R2VTopNavTabs({
    super.key,
    required this.activeIndex,
    required this.isDark,
  });

  /// Canonical routes, index-aligned with the labels below.
  static const List<String> routes = [
    '/home',
    '/aichat',
    '/explore',
    '/talent',
    '/settings',
  ];

  static const List<String> labels = [
    'Home',
    'AI Studio',
    'Marketplace',
    'Find Talent',
    'Settings',
  ];

  @override
  State<R2VTopNavTabs> createState() => _R2VTopNavTabsState();
}

class _R2VTopNavTabsState extends State<R2VTopNavTabs> {
  int? _hover;

  void _go(int i) {
    if (i == widget.activeIndex) return; // already on this page
    Navigator.pushReplacementNamed(context, R2VTopNavTabs.routes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final navCount = R2VTopNavTabs.labels.length;
    const indicatorWidth = 48.0;

    return LayoutBuilder(
      builder: (context, c) {
        final segmentWidth = c.maxWidth / navCount;
        final underlineRef = _hover ?? widget.activeIndex;
        final showUnderline = underlineRef >= 0 && underlineRef < navCount;
        final underlineLeft =
            underlineRef.clamp(0, navCount - 1) * segmentWidth +
                (segmentWidth - indicatorWidth) / 2;

        return SizedBox(
          // 46px tall so every tab has a comfortable 44–48px vertical hitbox.
          height: 46,
          child: Stack(
            children: [
              Row(
                children: List.generate(navCount, (i) {
                  final active = widget.activeIndex == i;
                  final hover = _hover == i;
                  final effective = active || hover;

                  return MouseRegion(
                    onEnter: (_) => setState(() => _hover = i),
                    onExit: (_) => setState(() => _hover = null),
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      // Opaque so the full segment (width + height) is tappable,
                      // not only the text.
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _go(i),
                      child: SizedBox(
                        width: segmentWidth,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 120),
                            style: TextStyle(
                              color: effective
                                  ? (isDark
                                      ? Colors.white
                                      : const Color(0xFF1E293B))
                                  : (isDark
                                      ? Colors.white60
                                      : Colors.black54),
                              fontWeight:
                                  effective ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 13.5,
                            ),
                            child: Text(
                              R2VTopNavTabs.labels[i],
                              // Never wrap — single line, no clipping.
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (showUnderline)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  left: underlineLeft,
                  bottom: 0,
                  child: Container(
                    width: indicatorWidth,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFBC70FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
