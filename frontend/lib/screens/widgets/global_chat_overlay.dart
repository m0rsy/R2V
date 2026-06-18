import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/r2v_api.dart';
import '../../utils/bubble_position_store.dart';
import 'r2v_section_nav.dart';

/// Wraps an authenticated page and overlays a floating chat button with an
/// unread badge in the bottom-right corner, so Messages is reachable from
/// every authenticated screen on both desktop and mobile.
///
/// Real-time: the badge refreshes on a short poll and whenever the user
/// returns from the chat page. TODO(realtime): replace the poll with a
/// WebSocket-driven unread stream when the backend exposes one.
class GlobalChatOverlay extends StatefulWidget {
  const GlobalChatOverlay({
    super.key,
    required this.child,
    this.showButton = true,
  });

  final Widget child;

  /// Hidden on the chat page itself (active state).
  final bool showButton;

  @override
  State<GlobalChatOverlay> createState() => _GlobalChatOverlayState();
}

class _GlobalChatOverlayState extends State<GlobalChatOverlay> {
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.showButton) {
      _loadUnread();
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _loadUnread());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final convs = await r2vChat.conversations();
      final total = convs.fold<int>(0, (sum, c) => sum + c.unreadCount);
      if (mounted) setState(() => _unread = total);
    } catch (_) {
      // The button still works without a badge.
    }
  }

  Future<void> _openChat() async {
    await Navigator.pushNamed(context, '/chat');
    _loadUnread();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (widget.showButton)
          // Full-screen drag layer; only the bubble itself is hit-testable, so
          // the page underneath stays fully interactive.
          Positioned.fill(
            child: _DraggableChatBubble(
              onTap: _openChat,
              child: _ChatFab(unread: _unread),
            ),
          ),
      ],
    );
  }
}

/// A floating bubble the user can drag anywhere on screen. Position is clamped
/// to stay fully visible, persisted as normalized fractions, and re-clamped on
/// resize. A tap (no meaningful movement) still triggers [onTap]; a drag moves
/// the bubble and never opens chat.
class _DraggableChatBubble extends StatefulWidget {
  const _DraggableChatBubble({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_DraggableChatBubble> createState() => _DraggableChatBubbleState();
}

class _DraggableChatBubbleState extends State<_DraggableChatBubble> {
  // Bubble footprint (54px circle + a little room for the unread badge) and the
  // minimum gap kept from every screen edge.
  static const double _size = 58;
  static const double _edgePad = 12;
  // Default resting spot (bottom-right), matching the previous fixed position.
  static const double _defaultRightInset = 20;
  static const double _defaultBottomInset = 24;

  // Absolute top-left while/after dragging in this session (null until first
  // drag or until a saved/normalized position resolves).
  double? _left;
  double? _top;
  // Persisted normalized position (0..1), loaded from local storage.
  Offset? _norm;
  bool _dragging = false;

  // Last rendered (clamped) geometry — used as the drag base and for saving.
  double _renderLeft = 0;
  double _renderTop = 0;
  double _lastW = 0;
  double _lastH = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final saved = await loadBubblePosition();
    if (saved != null && mounted) {
      setState(() => _norm = saved);
    }
  }

  double _clamp(double v, double max) {
    final hi = max < _edgePad ? _edgePad : max;
    return v.clamp(_edgePad, hi);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      // Base off the last clamped render so the bubble never "overshoots" the
      // edge and stick — it tracks the finger/cursor 1:1 within bounds.
      _left = _renderLeft + d.delta.dx;
      _top = _renderTop + d.delta.dy;
    });
  }

  void _onPanEnd() {
    setState(() => _dragging = false);
    if (_lastW <= 0 || _lastH <= 0) return;
    _norm = Offset(_renderLeft / _lastW, _renderTop / _lastH);
    saveBubblePosition(_norm!.dx, _norm!.dy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        _lastW = w;
        _lastH = h;

        // On mobile (< 900) a floating glass bottom nav (R2VSectionNav and the
        // home/talent equivalents) sits at the bottom. Reserve its footprint so
        // the bubble can never rest on top of — or be dragged below — the nav.
        final bool isMobile = w < 900;
        final double navReserve = isMobile
            ? R2VSectionNav.barFootprint +
                MediaQuery.of(context).padding.bottom +
                20
            : 0;

        final maxLeft = w - _size - _edgePad;
        final maxTop = h - _size - _edgePad - navReserve;

        // Pick the source of truth: an active session position, else a saved
        // normalized one, else the default bottom-right.
        double left;
        double top;
        if (_left != null) {
          left = _left!;
          top = _top!;
        } else if (_norm != null) {
          left = _norm!.dx * w;
          top = _norm!.dy * h;
        } else {
          left = w - _size - _defaultRightInset;
          top = h - _size - _defaultBottomInset - navReserve;
        }

        // Clamp every build so a resized/zoomed window keeps it on-screen.
        left = _clamp(left, maxLeft);
        top = _clamp(top, maxTop);
        _renderLeft = left;
        _renderTop = top;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: MouseRegion(
                cursor: _dragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab,
                child: GestureDetector(
                  // A pure tap still opens chat; a drag wins the gesture arena
                  // so chat never opens accidentally mid-drag.
                  onTap: widget.onTap,
                  onPanStart: (_) => setState(() => _dragging = true),
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: (_) => _onPanEnd(),
                  onPanCancel: () => setState(() => _dragging = false),
                  child: AnimatedScale(
                    scale: _dragging ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: SizedBox(
                      width: _size,
                      height: _size,
                      child: Center(child: widget.child),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Visual-only purple chat bubble with an unread badge. Gestures (tap + drag)
/// are handled by the surrounding [_DraggableChatBubble].
class _ChatFab extends StatelessWidget {
  const _ChatFab({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF8A4FFF),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8A4FFF).withOpacity(0.45),
                blurRadius: 18,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.chat_bubble_rounded,
              color: Colors.white, size: 24),
        ),
        if (unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF72585),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.black.withOpacity(0.4)),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
