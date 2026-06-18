import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/r2v_api.dart';
import '../api/api_exception.dart';
import '../main.dart'; // Needed for themeNotifier
import 'widgets/r2v_section_nav.dart';
import 'widgets/r2v_top_nav_tabs.dart';
import 'widgets/r2v_notification_bell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int selectedSection = 0;

  bool darkMode = false;
  bool notifyAI = true;
  bool notifyUpdates = true;

  bool _loadingProfile = false;
  bool _savingProfile = false;
  bool _emailVerified = false;
  bool _sendingVerify = false;
  String? _profileError;
  String _role = '';
  String? _avatarUrl;
  Map<String, dynamic> _profileMeta = {};

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    darkMode = themeNotifier.value == ThemeMode.dark;
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.of(context).size.width;
    final bool isWeb = w >= 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0414) : const Color(0xFFF8FAFC),
      // Body flows behind the floating LumaBar so the animated background shows
      // through (no flat strip behind the pill); mobile content reserves the
      // bar's footprint below.
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: MeshyParticleBackground(isDark: isDark)),
          Positioned.fill(child: _ReactHeroBackground(isDark: isDark)),
          SafeArea(
            child: isWeb ? _buildWebLayout(isDark) : _buildMobileLayout(isDark),
          ),
          // Mobile-only global section nav as a floating overlay (NOT
          // bottomNavigationBar, so no solid strip is reserved). Index 5 =
          // Profile/Settings. Desktop keeps its top nav.
          if (!isWeb)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: R2VSectionNav(currentIndex: 5),
            ),
        ],
      ),
    );
  }

  Widget _buildWebLayout(bool isDark) {
    final double w = MediaQuery.of(context).size.width;
    final double contentWidth = w > 1200 ? 1200 : w;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentWidth),
        child: Column(
          children: [
            const SizedBox(height: 20),
            _GlassTopBar(
              activeIndex: 4, // Settings is the 5th tab (index 4)
              isDark: isDark,
              onProfile: () => Navigator.pushNamed(context, '/profile'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSidebar(isDark),
                  const SizedBox(width: 24),
                  Expanded(child: _buildRightPanelCard(isDark)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _mobileHeader(isDark),
        ),
        const SizedBox(height: 14),
        // Mobile section switcher — exposes every section the desktop sidebar
        // has (Account · Security · Notifications · Appearance · Billing ·
        // Marketplace · Support) so mobile Settings is no longer stuck on
        // Account only.
        _mobileSectionChips(isDark),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            // Reserve the floating nav footprint so the danger area / Save
            // button is never hidden behind the bottom pill.
            padding: const EdgeInsets.fromLTRB(
                20, 0, 20, 32 + R2VSectionNav.barFootprint),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildRightPanelCard(isDark),
                const SizedBox(height: 18),
                _mobileDangerArea(isDark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileSectionChips(bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: _sections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = selectedSection == i;
          return GestureDetector(
            onTap: () => setState(() => selectedSection = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: active
                    ? const LinearGradient(colors: [Color(0xFFF72585), Color(0xFF9B5CFF)])
                    : null,
                color: active
                    ? null
                    : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_sections[i].icon, size: 15,
                      color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54)),
                  const SizedBox(width: 6),
                  Text(
                    _sections[i].label,
                    style: TextStyle(
                      color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _mobileDangerArea(bool isDark) {
    return _glassPanel(
      isDark: isDark,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _staticAction(
            label: "Logout", icon: Icons.logout_rounded, color: Colors.orange,
            onTap: _logout, isDark: isDark,
          ),
          const SizedBox(height: 12),
          _staticAction(
            label: "Delete Account", icon: Icons.delete_forever, color: Colors.red,
            onTap: _showDeleteDialog, isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isDark) {
    return _glassPanel(
      isDark: isDark,
      width: 270,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Settings",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Manage your account preferences",
            style: TextStyle(
              color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 26),
          for (int i = 0; i < _sections.length; i++) ...[
            _sideTab(_sections[i].label, _sections[i].icon, i, isDark),
            const SizedBox(height: 12),
          ],
          const Spacer(),
          _staticAction(
            label: "Logout",
            icon: Icons.logout_rounded,
            color: Colors.orange,
            onTap: _logout,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _staticAction(
            label: "Delete Account",
            icon: Icons.delete_forever,
            color: Colors.red,
            onTap: _showDeleteDialog,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _sideTab(String text, IconData icon, int index, bool isDark) {
    final bool active = selectedSection == index;

    return GestureDetector(
      onTap: () => setState(() => selectedSection = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: active 
              ? (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06)) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active 
                ? (isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.05)) 
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: active ? const Color(0xFFBC70FF) : (isDark ? Colors.white70 : Colors.black54),
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(
                color: active 
                    ? (isDark ? Colors.white : const Color(0xFF1E293B)) 
                    : (isDark ? Colors.white70 : Colors.black54),
                fontSize: 14.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _staticAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(isDark ? 0.15 : 0.1),
          border: Border.all(color: color.withOpacity(isDark ? 0.4 : 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Section list shared by the desktop sidebar and the mobile chip switcher so
  // the two layouts never drift apart.
  static const List<_SettingsSection> _sections = [
    _SettingsSection('Account', Icons.person),
    _SettingsSection('Security', Icons.lock),
    _SettingsSection('Notifications', Icons.notifications),
    _SettingsSection('Appearance', Icons.color_lens),
    _SettingsSection('Billing', Icons.credit_card),
    _SettingsSection('Marketplace', Icons.storefront_rounded),
    _SettingsSection('Support', Icons.help_outline_rounded),
  ];

  Widget _buildRightPanel(bool isDark) {
    switch (selectedSection) {
      case 0: return _buildAccountSection(isDark);
      case 1: return _buildPrivacySection(isDark);
      case 2: return _buildNotificationSection(isDark);
      case 3: return _buildAppearanceSection(isDark);
      case 4: return _buildSubscriptionSection(isDark);
      case 5: return _buildMarketplaceSection(isDark);
      case 6: return _buildSupportSection(isDark);
      default: return _buildAccountSection(isDark);
    }
  }

  Widget _buildAccountSection(bool isDark) {
    return _sectionWrapper(
      title: "Account Settings",
      subtitle: "Update your profile information and contact details.",
      isDark: isDark,
      children: [
        if (_loadingProfile)
          _infoBanner(icon: Icons.hourglass_bottom, message: "Loading profile details...", isDark: isDark),
        if (_profileError != null)
          _infoBanner(icon: Icons.info_outline, message: _profileError!, isDark: isDark),
        _profileHeader(isDark),
        const SizedBox(height: 20),
        _glassTextField(
          controller: _usernameController, label: "Display name", hint: "Your public profile name",
          icon: Icons.person_outline, enabled: !_savingProfile && !_loadingProfile, isDark: isDark,
        ),
        const SizedBox(height: 16),
        _glassTextField(
          controller: _bioController, label: "Bio", hint: "Tell people about yourself",
          icon: Icons.notes_outlined, enabled: !_savingProfile && !_loadingProfile, isDark: isDark,
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        _glassTextField(
          controller: _emailController, label: "Email", hint: "Email address",
          icon: Icons.email_outlined, enabled: false, isDark: isDark,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _emailVerifiedBadge(isDark),
            const Spacer(),
            if (!_emailVerified)
              TextButton(
                onPressed: _sendingVerify ? null : _resendVerification,
                child: Text(
                  _sendingVerify ? "Sending..." : "Verify now",
                  style: const TextStyle(color: Color(0xFFBC70FF), fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _glassTextField(
          controller: _phoneController, label: "Phone", hint: "Add a phone for recovery",
          icon: Icons.phone_outlined, enabled: !_savingProfile && !_loadingProfile, isDark: isDark,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/editprofile'),
            icon: const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFFBC70FF)),
            label: const Text("Edit full profile", style: TextStyle(color: Color(0xFFBC70FF), fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _savingProfile ? null : _saveProfile,
            icon: _savingProfile
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_savingProfile ? "Saving..." : "Save changes"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A4FFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacySection(bool isDark) {
    return _sectionWrapper(
      title: "Security", subtitle: "Keep your account secure with quick actions.", isDark: isDark,
      children: [
        _actionTile(
          icon: Icons.lock_reset, title: "Reset password", subtitle: "Send a reset email to secure your account.",
          actionLabel: "Send email", onTap: () => Navigator.pushNamed(context, '/forgot'), isDark: isDark,
        ),
        const SizedBox(height: 16),
        _actionTile(
          icon: _emailVerified ? Icons.verified_user_outlined : Icons.mark_email_unread_outlined,
          title: "Email verification",
          subtitle: _emailVerified ? "Your email is verified." : "Confirm your email to secure your account.",
          actionLabel: _emailVerified ? "Verified" : (_sendingVerify ? "Sending..." : "Verify"),
          onTap: _emailVerified || _sendingVerify ? null : _resendVerification, isDark: isDark,
        ),
        const SizedBox(height: 16),
        _actionTile(
          icon: Icons.shield_outlined, title: "Two-factor authentication", subtitle: "Add an extra layer of protection to your login.",
          actionLabel: "Coming soon", onTap: null, isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildNotificationSection(bool isDark) {
    return _sectionWrapper(
      title: "Notifications", subtitle: "Pick what you want to hear about.", isDark: isDark,
      children: [
        _switchTile(label: "AI model ready", description: "Get alerted when your generation finishes.", value: notifyAI, onChanged: (v) => setState(() => notifyAI = v), isDark: isDark),
        const SizedBox(height: 12),
        _switchTile(label: "App updates", description: "Product news and new feature highlights.", value: notifyUpdates, onChanged: (v) => setState(() => notifyUpdates = v), isDark: isDark),
      ],
    );
  }

  Widget _buildAppearanceSection(bool isDark) {
    return _sectionWrapper(
      title: "Appearance", subtitle: "Tune the look and feel to your taste.", isDark: isDark,
      children: [
        _switchTile(
          label: "Dark mode", description: "Switch between light and dark ambiance.",
          value: darkMode,
          onChanged: (v) {
            setState(() {
              darkMode = v;
              themeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
            });
          },
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        _actionTile(
          icon: Icons.palette_outlined, title: "Theme accent", subtitle: "Customize your highlight color.",
          actionLabel: "Default", onTap: null, isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSubscriptionSection(bool isDark) {
    return _sectionWrapper(
      title: "Subscription & Billing", subtitle: "Manage your plan and payment preferences.", isDark: isDark,
      children: [
        _subscriptionSummaryCard(),
        const SizedBox(height: 18),
        _paymentMethodCard(isDark),
        const SizedBox(height: 18),
        _billingNoteCard(isDark),
      ],
    );
  }

  Widget _subscriptionSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF8A4FFF), Color(0xFFBC70FF)]),
        boxShadow: [BoxShadow(color: const Color(0xFF8A4FFF).withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("Current Plan", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text("R2V Pro – Monthly", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text("\$14.99 / month · Renews on Jan 20, 2026", style: TextStyle(color: Colors.white, fontSize: 13.5)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final url = await r2vBilling.checkoutSubscription();
                if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFF8A4FFF),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text("Manage Plan", style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.03),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Color(0xFF4895EF), Color(0xFF4CC9F0)]),
            ),
            child: const Icon(Icons.credit_card, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Payment Method", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text("Visa •••• 4821", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                final url = await r2vBilling.checkoutSubscription();
                if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            child: const Text("Change", style: TextStyle(color: Color(0xFF4CC9F0), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _billingNoteCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: isDark ? Colors.white70 : Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Billing history and invoices will appear here in a future update.",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileHeader(bool isDark) {
    final name = _usernameController.text.trim().isEmpty ? 'Your profile' : _usernameController.text.trim();
    final hasAvatar = (_avatarUrl != null && _avatarUrl!.trim().isNotEmpty);
    final roleLabel = _role.isEmpty ? null : (_role[0].toUpperCase() + _role.substring(1));
    return Row(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF8A4FFF), Color(0xFFBC70FF)]),
            image: hasAvatar
                ? DecorationImage(image: NetworkImage(_avatarUrl!), fit: BoxFit.cover)
                : null,
            boxShadow: [BoxShadow(color: const Color(0xFF8A4FFF).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: hasAvatar ? null : const Icon(Icons.person, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (roleLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBC70FF).withOpacity(isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFBC70FF).withOpacity(0.5)),
                  ),
                  child: Text(roleLabel, style: const TextStyle(color: Color(0xFFBC70FF), fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarketplaceSection(bool isDark) {
    return _sectionWrapper(
      title: "Marketplace", subtitle: "Manage your creations and saved items.", isDark: isDark,
      children: [
        _actionTile(
          icon: Icons.storefront_rounded, title: "Browse marketplace", subtitle: "Explore 3D assets from the community.",
          actionLabel: "Open", onTap: () => Navigator.pushNamed(context, '/explore'), isDark: isDark,
        ),
        const SizedBox(height: 16),
        _actionTile(
          icon: Icons.inventory_2_outlined, title: "My published assets", subtitle: "View and manage assets you've published.",
          actionLabel: "View", onTap: () => Navigator.pushNamed(context, '/profile'), isDark: isDark,
        ),
        const SizedBox(height: 16),
        _actionTile(
          icon: Icons.bookmark_border_rounded, title: "Saved assets", subtitle: "Items you bookmarked for later.",
          actionLabel: "View", onTap: () => Navigator.pushNamed(context, '/explore'), isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSupportSection(bool isDark) {
    return _sectionWrapper(
      title: "Support", subtitle: "We're here to help.", isDark: isDark,
      children: [
        _actionTile(
          icon: Icons.mail_outline_rounded, title: "Contact support", subtitle: "Email our team at support@realtwovirtual.com.",
          actionLabel: "Email", onTap: _contactSupport, isDark: isDark,
        ),
        const SizedBox(height: 16),
        _actionTile(
          icon: Icons.public_rounded, title: "Visit website", subtitle: "realtwovirtual.com",
          actionLabel: "Open",
          onTap: () async {
            try { await launchUrl(Uri.parse('https://realtwovirtual.com'), mode: LaunchMode.externalApplication); } catch (_) {}
          },
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _sectionWrapper({required String title, String? subtitle, required List<Widget> children, required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 24, fontWeight: FontWeight.w900)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54, fontSize: 13.5)),
          ],
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _glassTextField({required TextEditingController controller, required String label, required String hint, required IconData icon, bool enabled = true, required bool isDark, int maxLines = 1}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B)),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.black54),
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        hintStyle: TextStyle(color: isDark ? Colors.white.withOpacity(0.4) : Colors.black38),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(enabled ? 0.08 : 0.04) : Colors.black.withOpacity(enabled ? 0.04 : 0.02),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFBC70FF), width: 1.5)),
      ),
    );
  }

  Widget _switchTile({required String label, required String description, required bool value, required ValueChanged<bool> onChanged, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05)),
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.03),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54, fontSize: 13)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFFBC70FF)),
        ],
      ),
    );
  }

  Widget _actionTile({required IconData icon, required String title, required String subtitle, required String actionLabel, required VoidCallback? onTap, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05)),
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.03),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05)),
            child: Icon(icon, color: isDark ? Colors.white : const Color(0xFF1E293B)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54, fontSize: 13)),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(actionLabel, style: TextStyle(color: onTap == null ? (isDark ? Colors.white38 : Colors.black26) : const Color(0xFFBC70FF), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner({required IconData icon, required String message, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.04),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: isDark ? Colors.white70 : Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87, fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanelCard(bool isDark) {
    return _glassPanel(isDark: isDark, padding: EdgeInsets.zero, child: _buildRightPanel(isDark));
  }

  Widget _glassPanel({required Widget child, required bool isDark, EdgeInsetsGeometry padding = const EdgeInsets.all(24), double? width}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width, padding: padding,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.9)),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _mobileHeader(bool isDark) {
    return _glassPanel(
      isDark: isDark,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.settings, color: Color(0xFFBC70FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Settings",
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          // Mobile notification bell — top-right header only. The bottom LumaBar
          // stays unchanged (no bell there).
          R2VNotificationBell(isDark: isDark, size: 36),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
            icon: Icon(Icons.home_outlined, color: isDark ? Colors.white70 : Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try { await r2vAuth.logout(); } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/signin');
  }

  void _showDeleteDialog() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1B20) : Colors.white,
        title: const Text("Delete Account", style: TextStyle(color: Colors.red)),
        content: Text("This action is permanent and cannot be undone.", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          TextButton(
            onPressed: () async {
              try {
                await r2vProfile.deleteAccount();
                await r2vAuth.logout();
                if (mounted) Navigator.pushReplacementNamed(context, '/signin');
              } catch (_) {}
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _emailVerifiedBadge(bool isDark) {
    final bool verified = _emailVerified;
    final Color color = verified ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(verified ? Icons.verified_rounded : Icons.error_outline_rounded, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              verified ? "Verified" : "Not verified",
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resendVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _sendingVerify) return;
    setState(() => _sendingVerify = true);
    try {
      await r2vEmailVerification.requestCode(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code sent — check your email.')),
      );
      Navigator.pushNamed(context, '/verifycode', arguments: email);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to send verification email')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingVerify = false);
    }
  }

  Future<void> _contactSupport() async {
    final uri = Uri.parse('mailto:support@realtwovirtual.com?subject=R2V%20Support');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email us at support@realtwovirtual.com')),
        );
      }
    }
  }

  Future<void> _loadProfile() async {
    setState(() { _loadingProfile = true; _profileError = null; });
    try {
      final data = await r2vProfile.me();
      if (!mounted) return;
      setState(() {
        _usernameController.text = data.username;
        _emailController.text = data.email;
        _bioController.text = data.bio ?? '';
        _role = data.role;
        _avatarUrl = data.avatarUrl;
        _emailVerified = data.emailVerified;
        _profileMeta = Map<String, dynamic>.from(data.meta);
        _phoneController.text = _profileMeta['phone']?.toString() ?? '';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _profileError = e.message);
    } catch (_) {
      if (mounted) setState(() => _profileError = 'Unable to load profile settings');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() { _savingProfile = true; _profileError = null; });
    try {
      final phone = _phoneController.text.trim();
      final updatedMeta = Map<String, dynamic>.from(_profileMeta);
      if (phone.isEmpty) updatedMeta.remove('phone'); else updatedMeta['phone'] = phone;

      final data = await r2vProfile.update(
        username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        bio: _bioController.text.trim(),
        meta: updatedMeta,
      );
      if (!mounted) return;
      setState(() {
        _profileMeta = Map<String, dynamic>.from(data.meta);
        _usernameController.text = data.username;
        _bioController.text = data.bio ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings updated successfully')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _profileError = e.message);
    } catch (_) {
      if (mounted) setState(() => _profileError = 'Unable to save settings');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }
}

class _SettingsSection {
  final String label;
  final IconData icon;
  const _SettingsSection(this.label, this.icon);
}

// ---------------------------------------------------------
// TOP BAR
// ---------------------------------------------------------
class _GlassTopBar extends StatelessWidget {
  final int activeIndex;
  final VoidCallback onProfile;
  final bool isDark;

  const _GlassTopBar({
    required this.activeIndex,
    required this.onProfile,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9)),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 26, color: Color(0xFFBC70FF)),
              const SizedBox(width: 8),
              Text(
                "R2V SETTINGS",
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              SizedBox(
                width: 560,
                child: R2VTopNavTabs(activeIndex: activeIndex, isDark: isDark),
              ),
              const SizedBox(width: 16),
              R2VNotificationBell(isDark: isDark),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onProfile,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, color: isDark ? Colors.white : const Color(0xFF1E293B), size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// BACKGROUNDS
// ---------------------------------------------------------

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
              top: -150, right: -50,
              child: Transform.rotate(
                angle: -0.35,
                child: Row(
                  children: [
                    _GradientBlob(isDark: isDark), const SizedBox(width: 50),
                    _GradientBlob(isDark: isDark), const SizedBox(width: 50),
                    _GradientBlob(isDark: isDark),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -50, right: -150,
              child: Transform.rotate(
                angle: -0.35, 
                child: Row(
                  children: [
                    _GradientBlob(isDark: isDark), const SizedBox(width: 50),
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
        width: 140, height: 400,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark 
                ? [Colors.white.withOpacity(0.15), Colors.blue.shade300.withOpacity(0.35)]
                : [const Color(0xFFBC70FF).withOpacity(0.25), const Color(0xFF4895EF).withOpacity(0.25)],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
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
      if (!mounted || _size == Size.zero) return;
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
  void dispose() { _ticker.dispose(); super.dispose(); }

  void _ensureParticles(Size s) {
    if (s == Size.zero) return;
    int target = ((s.width * s.height) / 18000).round().clamp(35, 95);
    if (_ps.length == target) return;
    _ps = List.generate(target, (i) {
      final pos = Offset(_rng.nextDouble() * s.width, _rng.nextDouble() * s.height);
      final vel = Offset(cos(_rng.nextDouble() * pi * 2), sin(_rng.nextDouble() * pi * 2)) * (8 + _rng.nextDouble() * 18);
      return _Particle(pos: pos, vel: vel, radius: 1.2 + _rng.nextDouble() * 1.9);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final s = Size(c.maxWidth, c.maxHeight);
      if (_size != s) { _size = s; _ensureParticles(s); }
      return MouseRegion(
        onHover: (e) { _hasMouse = true; _mouse = e.localPosition; },
        onExit: (_) => _hasMouse = false,
        child: CustomPaint(painter: _MeshPainter(particles: _ps, time: _t, size: s, mouse: _mouse, hasMouse: _hasMouse, isDark: widget.isDark)),
      );
    });
  }
}

class _Particle { Offset pos; Offset vel; final double radius; _Particle({required this.pos, required this.vel, required this.radius}); }

class _MeshPainter extends CustomPainter {
  final List<_Particle> particles; final double time; final Size size; final Offset mouse; final bool hasMouse; final bool isDark;
  _MeshPainter({required this.particles, required this.time, required this.size, required this.mouse, required this.hasMouse, required this.isDark});

  @override
  void paint(Canvas canvas, Size _) {
    final rect = Offset.zero & size;
    final bgColors = isDark 
        ? const [Color(0xFF0F1118), Color(0xFF141625), Color(0xFF0B0D14)]
        : const [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFE2E8F0)];
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bgColors, stops: const [0.0, 0.55, 1.0]).createShader(rect));

    void glowBlob(Offset c, double r, Color col, double a) => canvas.drawCircle(c, r, Paint()..color = col.withOpacity(a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90));
    final center = Offset(size.width * 0.55, size.height * 0.35);
    final wobble = Offset(sin(time * 0.5) * 40, cos(time * 0.45) * 30);
    glowBlob(center + wobble, 280, isDark ? const Color(0xFF8A4FFF) : const Color(0xFFA855F7), isDark ? 0.18 : 0.12);
    glowBlob(Offset(size.width * 0.25, size.height * 0.70) + Offset(cos(time * 0.35) * 35, sin(time * 0.32) * 28), 240, isDark ? const Color(0xFF4895EF) : const Color(0xFF38BDF8), isDark ? 0.14 : 0.10);

    Offset parallax = hasMouse ? Offset((mouse.dx / max(1.0, size.width) - 0.5) * 18, (mouse.dy / max(1.0, size.height) - 0.5) * 18) : Offset.zero;
    final connectDist = min(size.width, size.height) * 0.15, connectDist2 = connectDist * connectDist;
    final linePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1;

    for (int i = 0; i < particles.length; i++) {
      final ap = particles[i].pos + parallax * 0.25;
      for (int j = i + 1; j < particles.length; j++) {
        final bp = particles[j].pos + parallax * 0.25;
        final d2 = (ap.dx - bp.dx) * (ap.dx - bp.dx) + (ap.dy - bp.dy) * (ap.dy - bp.dy);
        if (d2 < connectDist2) {
          final t = 1.0 - (sqrt(d2) / connectDist);
          linePaint.color = isDark ? Colors.white.withOpacity(0.06 * t) : const Color(0xFF8A4FFF).withOpacity(0.15 * t);
          canvas.drawLine(ap, bp, linePaint);
        }
      }
    }
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      dotPaint.color = isDark ? Colors.white.withOpacity(0.12) : const Color(0xFF8A4FFF).withOpacity(0.25);
      canvas.drawCircle(p.pos + parallax * 0.6, p.radius, dotPaint);
    }
    final vignetteColors = isDark ? [Colors.transparent, Colors.black.withOpacity(0.55)] : [Colors.transparent, Colors.white.withOpacity(0.4)];
    canvas.drawRect(rect, Paint()..shader = RadialGradient(center: Alignment.center, radius: 1.15, colors: vignetteColors, stops: const [0.55, 1.0]).createShader(rect));
  }
  @override bool shouldRepaint(covariant _MeshPainter oldDelegate) => true;
}
