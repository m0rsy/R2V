import 'dart:ui';
import 'package:flutter/material.dart';

import '../../api/r2v_api.dart';
import '../../theme/app_colors.dart';

class WebTopBar extends StatefulWidget {
  /// activeIndex:
  /// 0 = Home, 1 = AI Studio, 2 = Marketplace, 3 = Freelance, 4 = Settings
  final int activeIndex;

  /// Optional avatar image
  final ImageProvider? avatar;

  const WebTopBar({
    super.key,
    required this.activeIndex,
    this.avatar,
  });

  @override
  State<WebTopBar> createState() => _WebTopBarState();
}

class _WebTopBarState extends State<WebTopBar> {
  int? hoverIndex;
  bool showProfileMenu = false;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    try {
      final convs = await r2vChat.conversations();
      final total = convs.fold<int>(0, (sum, c) => sum + c.unreadCount);
      if (mounted) setState(() => _unread = total);
    } catch (_) {
      // Silently ignore — the DM button still works without a badge.
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Added Freelance
    final tabs = ["Home", "AI Studio", "Marketplace", "Find Talent", "Settings"];

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              // LOGO
              const Icon(Icons.auto_awesome_rounded, size: 26, color: AppColors.brandPurple),
              const SizedBox(width: 8),

              const Text(
                "R2V Studio",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const Spacer(),

              // NAVIGATION TABS WITH UNDERLINE
              SizedBox(
                width: 520, // ✅ Expanded from 400 to 520
                height: 38,
                child: _navTabs(tabs),
              ),

              const SizedBox(width: 20),

              // Chat icon
              _chatButton(context),

              const SizedBox(width: 12),

              // Notifications icon
              _notificationButton(),

              const SizedBox(width: 16),

              // Profile Avatar
              _profileAvatar(context),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // NAVIGATION TABS
  // ──────────────────────────────────────────────────────────────

  Widget _navTabs(List<String> tabs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = constraints.maxWidth / tabs.length;
        const underlineWidth = 48.0;

        final active = hoverIndex ?? widget.activeIndex;

        final underlineLeft = active * segmentWidth + (segmentWidth - underlineWidth) / 2;

        return Stack(
          children: [
            // Tab labels
            Row(
              children: List.generate(tabs.length, (i) {
                final bool highlight = (hoverIndex == i) || (widget.activeIndex == i);

                return MouseRegion(
                  onEnter: (_) => setState(() => hoverIndex = i),
                  onExit: (_) => setState(() => hoverIndex = null),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _navigate(i),
                    child: SizedBox(
                      width: segmentWidth,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 130),
                          style: TextStyle(
                            color: highlight ? Colors.white : Colors.white.withOpacity(0.7),
                            fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                            fontSize: 13.5,
                          ),
                          child: Text(tabs[i]),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),

            // Underline animation
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              left: underlineLeft,
              bottom: 0,
              child: Container(
                width: underlineWidth,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.brandPurple,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
  // NOTIFICATION ICON
  // ──────────────────────────────────────────────────────────────

  Widget _chatButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          await Navigator.pushNamed(context, "/chat");
          _loadUnread();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white, size: 20),
            ),
            if (_unread > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black.withOpacity(0.35)),
                  ),
                  child: Text(
                    _unread > 99 ? '99+' : '$_unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notificationButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 20),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // PROFILE AVATAR + POPUP MENU
  // ──────────────────────────────────────────────────────────────

  Widget _profileAvatar(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => setState(() => showProfileMenu = !showProfileMenu),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.4)),
              image: DecorationImage(
                fit: BoxFit.cover,
                image: widget.avatar ?? const AssetImage("assets/R2Vlogo.png"),
              ),
            ),
          ),
        ),

        if (showProfileMenu)
          Positioned(
            right: 0,
            top: 48,
            child: _profileMenu(context),
          ),
      ],
    );
  }

  Widget _profileMenu(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: 170,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _menuItem(Icons.person, "View Profile", () {
                setState(() => showProfileMenu = false);
                Navigator.pushNamed(context, "/profile");
              }),
              _menuItem(Icons.settings, "Settings", () {
                setState(() => showProfileMenu = false);
                Navigator.pushNamed(context, "/settings");
              }),
              _menuItem(Icons.logout_rounded, "Logout", _logout),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.white.withOpacity(0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    setState(() => showProfileMenu = false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await r2vAuth.logout();
    } catch (_) {
      // Ignore network/logout errors — local tokens are cleared regardless.
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/signin', (r) => false);
  }

  // ──────────────────────────────────────────────────────────────
  // ROUTING
  // ──────────────────────────────────────────────────────────────

  void _navigate(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, "/home");
        break;
      case 1:
        Navigator.pushReplacementNamed(context, "/aichat");
        break;
      case 2:
        Navigator.pushReplacementNamed(context, "/explore");
        break;
      case 3:
        Navigator.pushReplacementNamed(context, "/talent");
        break;
      case 4:
        Navigator.pushReplacementNamed(context, "/settings"); // ✅ Moved Settings to 4
        break;
    }
  }
}
