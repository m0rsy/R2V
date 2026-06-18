import 'dart:ui';
import 'package:flutter/material.dart';

import '../../api/r2v_api.dart';
import '../../api/notifications_service.dart';

/// Premium notification bell + glass popover, reusable on desktop and mobile.
///
/// - Circular glass button with a hover glow and an unread badge.
/// - Tapping opens a dark-glass popover anchored under the bell (via an
///   [OverlayEntry] + [CompositedTransformFollower]); tapping outside or an item
///   closes it.
/// - Wired to the real backend (`/notifications`): it fetches the list, derives
///   the unread count, marks items read on tap, and supports "Mark all as read"
///   by marking each unread item (no bulk endpoint exists). No fake data — if
///   the list is empty it shows a clean empty state.
class R2VNotificationBell extends StatefulWidget {
  /// Optional theme override; defaults to the ambient [Theme] brightness.
  final bool? isDark;
  final double size;

  const R2VNotificationBell({super.key, this.isDark, this.size = 38});

  @override
  State<R2VNotificationBell> createState() => _R2VNotificationBellState();
}

class _R2VNotificationBellState extends State<R2VNotificationBell> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;
  bool _hover = false;
  bool _loading = false;
  List<R2VNotification> _items = const [];

  int get _unread => _items.where((n) => !n.isRead).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  bool get _isDark =>
      widget.isDark ?? (Theme.of(context).brightness == Brightness.dark);

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final items = await r2vNotifications.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      // Non-blocking: keep whatever we had and just stop the spinner. Never show
      // fabricated notifications when the backend is briefly unavailable.
      if (!mounted) return;
      setState(() => _loading = false);
    }
    _entry?.markNeedsBuild();
  }

  void _toggle() => _open ? _close() : _openPanel();

  void _openPanel() {
    _entry = OverlayEntry(builder: _buildPopover);
    Overlay.of(context).insert(_entry!);
    setState(() => _open = true);
    _load(); // refresh on open
  }

  void _close() {
    _removeOverlay();
    if (mounted) setState(() => _open = false);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _markRead(R2VNotification n) async {
    if (n.isRead) return;
    setState(() {
      _items = [
        for (final x in _items)
          if (x.id == n.id)
            R2VNotification(
                id: x.id,
                type: x.type,
                payload: x.payload,
                isRead: true,
                createdAt: x.createdAt)
          else
            x
      ];
    });
    _entry?.markNeedsBuild();
    try {
      await r2vNotifications.markRead(n.id);
    } catch (_) {
      // Best-effort; the UI already reflects it.
    }
  }

  Future<void> _markAllRead() async {
    final unread = _items.where((n) => !n.isRead).toList();
    setState(() {
      _items = [
        for (final x in _items)
          R2VNotification(
              id: x.id,
              type: x.type,
              payload: x.payload,
              isRead: true,
              createdAt: x.createdAt)
      ];
    });
    _entry?.markNeedsBuild();
    for (final n in unread) {
      try {
        await r2vNotifications.markRead(n.id);
      } catch (_) {/* best-effort */}
    }
  }

  // ── Bell button ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    final size = widget.size;
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withOpacity(_open || _hover ? 0.18 : 0.12)
                        : Colors.black.withOpacity(_open || _hover ? 0.08 : 0.05),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.14)
                          : Colors.black.withOpacity(0.08),
                    ),
                    boxShadow: (_open || _hover)
                        ? [
                            BoxShadow(
                              color: const Color(0xFF8A4FFF).withOpacity(0.35),
                              blurRadius: 14,
                              spreadRadius: -2,
                            ),
                          ]
                        : const [],
                  ),
                  child: Icon(
                    Icons.notifications_rounded,
                    size: size * 0.5,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                if (_unread > 0)
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF72585),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF0C0414)
                              : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        _unread > 9 ? '9+' : '$_unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Popover ─────────────────────────────────────────────────────────────
  Widget _buildPopover(BuildContext context) {
    final isDark = _isDark;
    final screen = MediaQuery.of(context).size;
    final panelWidth = screen.width < 380 ? screen.width - 24 : 340.0;

    return Stack(
      children: [
        // Tap-outside barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 10),
          child: Align(
            alignment: Alignment.topRight,
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    width: panelWidth,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF120B26).withOpacity(0.92)
                          : Colors.white.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.12)
                            : Colors.black.withOpacity(0.06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.5 : 0.16),
                          blurRadius: 30,
                          spreadRadius: -6,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _popoverHeader(isDark),
                        Divider(
                          height: 1,
                          color: isDark
                              ? Colors.white.withOpacity(0.10)
                              : Colors.black.withOpacity(0.06),
                        ),
                        _popoverBody(isDark),
                      ],
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

  Widget _popoverHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(
        children: [
          Text(
            "Notifications",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (_unread > 0)
            GestureDetector(
              onTap: _markAllRead,
              behavior: HitTestBehavior.opaque,
              child: Text(
                "Mark all as read",
                style: TextStyle(
                  color: const Color(0xFFBC70FF),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _popoverBody(bool isDark) {
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 30),
        child: Column(
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 30,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 10),
            Text(
              _loading ? "Loading…" : "No notifications yet",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!_loading) ...[
              const SizedBox(height: 4),
              Text(
                "You're all caught up.",
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: _items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 56,
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
        ),
        itemBuilder: (_, i) => _tile(_items[i], isDark),
      ),
    );
  }

  Widget _tile(R2VNotification n, bool isDark) {
    final accent = _accentFor(n.type);
    return InkWell(
      onTap: () => _markRead(n),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withOpacity(isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(n.type), size: 16, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 13.5,
                      fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  if (n.message != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      n.message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    _ago(n.createdAt),
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!n.isRead)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFF72585),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    final t = type.toLowerCase();
    if (t.contains('order') || t.contains('purchase')) {
      return Icons.receipt_long_rounded;
    }
    if (t.contains('message') || t.contains('chat')) {
      return Icons.chat_bubble_rounded;
    }
    if (t.contains('follow')) return Icons.person_add_rounded;
    if (t.contains('like')) return Icons.favorite_rounded;
    if (t.contains('job') || t.contains('model') || t.contains('generation')) {
      return Icons.auto_awesome_rounded;
    }
    return Icons.notifications_rounded;
  }

  Color _accentFor(String type) {
    final t = type.toLowerCase();
    if (t.contains('order') || t.contains('purchase')) {
      return const Color(0xFF22C55E);
    }
    if (t.contains('message') || t.contains('chat')) {
      return const Color(0xFF4CC9F0);
    }
    if (t.contains('like') || t.contains('follow')) {
      return const Color(0xFFF72585);
    }
    return const Color(0xFF8A4FFF);
  }

  String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }
}
