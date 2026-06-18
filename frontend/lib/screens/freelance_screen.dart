import 'dart:async';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_exception.dart';
import '../api/freelance_service.dart';
import '../api/r2v_api.dart';
import '../api/recording_bytes.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/responsive.dart';
import '../widgets/ui/app_states.dart';
import '../widgets/ui/app_pill.dart';
import 'widgets/r2v_glass.dart';
import 'widgets/r2v_section_nav.dart'; // global mobile LumaBar nav

enum TalentPageMode {
  home,
  talents,
  talentDetail,
  services,
  serviceDetail,
  postProject,
  orders,
  orderDetail,
  chat,
  apply,
  dashboard,
}

const _categories = [
  '3D Modeling',
  'Texturing',
  'Rigging',
  'Animation',
  'Game Assets',
  '3D Model Cleanup',
  'AI Model Improvement',
  'Product Visualization',
  'Architecture Models',
  '3D Printing Preparation',
];

class TalentScreen extends StatefulWidget {
  const TalentScreen({
    super.key,
    required this.mode,
    this.id,
    this.prefill,
    this.search,
    this.category,
  });
  final TalentPageMode mode;
  final String? id;
  final Map<String, dynamic>? prefill;
  final String? search;
  final String? category;

  @override
  State<TalentScreen> createState() => _TalentScreenState();
}

class _TalentScreenState extends State<TalentScreen> {
  String _search = '';
  String? _category; // null = all categories
  Future<List<FlService>>? _servicesFuture;
  final _serviceSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search = widget.search ?? '';
    final c = widget.category;
    _category = (c != null && c.isNotEmpty) ? c : null;
    _serviceSearchController.text = _search;
  }

  @override
  void dispose() {
    _serviceSearchController.dispose();
    super.dispose();
  }

  Future<List<FlService>> _loadServices() {
    return _servicesFuture ??= r2vFreelance.services(
      search: _search,
      category: _category,
    );
  }

  void _reloadServices() {
    setState(() {
      _servicesFuture = r2vFreelance.services(
        search: _search,
        category: _category,
      );
    });
  }

  // Glass top-pill / bottom-bar navigation destinations.
  static const List<R2VNavItem> _navItems = [
    R2VNavItem('Marketplace', Icons.storefront_rounded),
    R2VNavItem('Services', Icons.grid_view_rounded),
    R2VNavItem('Orders', Icons.receipt_long_rounded),
    R2VNavItem('Dashboard', Icons.dashboard_rounded),
    R2VNavItem('Apply', Icons.workspace_premium_rounded),
  ];

  static const List<String> _navRoutes = [
    '/talent',
    '/talent/services',
    '/talent/my-orders',
    '/talent/dashboard',
    '/talent/become-talent',
  ];

  int get _activeNavIndex {
    switch (widget.mode) {
      case TalentPageMode.services:
      case TalentPageMode.serviceDetail:
        return 1;
      case TalentPageMode.orders:
      case TalentPageMode.orderDetail:
      case TalentPageMode.chat:
        return 2;
      case TalentPageMode.dashboard:
        return 3;
      case TalentPageMode.apply:
        return 4;
      case TalentPageMode.home:
      case TalentPageMode.talents:
      case TalentPageMode.talentDetail:
      case TalentPageMode.postProject:
        return 0;
    }
  }

  void _navTo(int i) {
    if (i == _activeNavIndex) return;
    Navigator.pushReplacementNamed(context, _navRoutes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWeb = MediaQuery.of(context).size.width >= 900;

    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.maxContent),
        child: switch (widget.mode) {
          TalentPageMode.home => _home(),
          TalentPageMode.talents => _talents(),
          TalentPageMode.talentDetail => _talentDetail(widget.id ?? ''),
          TalentPageMode.services => _services(),
          TalentPageMode.serviceDetail => _serviceDetail(widget.id ?? ''),
          TalentPageMode.postProject => _postProject(),
          TalentPageMode.orders => _orders(),
          TalentPageMode.orderDetail => _orderDetail(widget.id ?? ''),
          TalentPageMode.chat => _chat(widget.id ?? ''),
          TalentPageMode.apply => _apply(),
          TalentPageMode.dashboard => _dashboard(),
        },
      ),
    );

    return Scaffold(
      backgroundColor: isDark ? R2VBrand.bgDark : R2VBrand.bgLight,
      // Body flows behind the floating LumaBar so the animated background shows
      // through (no flat strip behind the pill).
      extendBody: true,
      body: Stack(
        children: [
          // Use the plain opaque mesh (it already paints its own glow blobs)
          // rather than R2VAnimatedBackground, whose extra ImageFiltered(blur:90)
          // hero layer nested in a RepaintBoundary could clip/darken at the
          // bottom edge and read as a dark strip behind the floating nav.
          Positioned.fill(child: MeshyParticleBackground(isDark: isDark)),
          SafeArea(
            child: isWeb
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: Breakpoints.maxContent,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: R2VGlassTopNav(
                              brand: 'R2V Talent',
                              items: _navItems,
                              activeIndex: _activeNavIndex,
                              onSelect: _navTo,
                              onBack: () => Navigator.canPop(context)
                                  ? Navigator.pop(context)
                                  : Navigator.pushReplacementNamed(
                                      context,
                                      '/home',
                                    ),
                              onProfile: () =>
                                  Navigator.pushNamed(context, '/profile'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(child: content),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      const SizedBox(height: 8),
                      _mobileSubNav(isDark),
                      const SizedBox(height: 8),
                      // Reserve the floating nav's footprint so list content
                      // never hides behind the bottom pill.
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              bottom: R2VSectionNav.barFootprint),
                          child: content,
                        ),
                      ),
                    ],
                  ),
          ),
          // Mobile-only GLOBAL section nav (Home · AI · Scan · Market · Talent ·
          // Profile) as a floating overlay — NOT bottomNavigationBar, so no
          // solid strip is reserved. Index 4 = Talent. The Talent sub-sections
          // live in the top chip row (_mobileSubNav). Desktop keeps its top nav.
          if (!isWeb)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: R2VSectionNav(currentIndex: 4),
            ),
        ],
      ),
    );
  }

  /// Secondary horizontal chip row for Talent's own sections (Marketplace ·
  /// Services · Orders · Dashboard · Apply). Shown only on mobile, where the
  /// bottom bar is reserved for the global section nav.
  Widget _mobileSubNav(bool isDark) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: _navItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = i == _activeNavIndex;
          return GestureDetector(
            onTap: () => _navTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: active
                    ? const LinearGradient(
                        colors: [Color(0xFFF72585), Color(0xFF9B5CFF)],
                      )
                    : null,
                color: active
                    ? null
                    : (isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04)),
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : (isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.black.withOpacity(0.08)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _navItems[i].icon,
                    size: 16,
                    color: active
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _navItems[i].label,
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.black54),
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

  Widget _home() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        r2vFreelance.freelancers(),
        r2vFreelance.services(),
      ]),
      builder: (context, snap) {
        final talents = (snap.data?[0] as List<FreelanceProfile>? ?? const [])
            .take(4)
            .toList();
        final services = (snap.data?[1] as List<FlService>? ?? const [])
            .take(4)
            .toList();
            
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _hero(),
              const SizedBox(height: 18),
              _searchBox('Search 3D talents or services...', (v) {
                setState(() => _search = v);
                Navigator.pushNamed(
                  context,
                  '/talent/services',
                  arguments: {'search': v},
                );
              }),
              const SizedBox(height: 18),
              _sectionTitle('Categories'),
              Wrap(
                spacing: 10, // Increased spacing for a cleaner look
                runSpacing: 10,
                children: [
                  for (final c in _categories)
                    _buildActionGlassChip(
                      c,
                      () => Navigator.pushNamed(
                        context,
                        '/talent/services',
                        arguments: {'category': c},
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _sectionTitle('Featured talents'),
              if (snap.connectionState == ConnectionState.waiting)
                const _Loading()
              else if (talents.isEmpty)
                const _Empty('No approved talents yet.')
              else
                ResponsiveGrid(
                  desktopColumns: 2,
                  children: [for (final t in talents) _TalentTile(t)],
                ),
              const SizedBox(height: 24),
              _sectionTitle('Popular services'),
              if (services.isEmpty)
                const _Empty('No active services yet.')
              else
                ResponsiveGrid(
                  desktopColumns: 2,
                  children: [for (final s in services) _ServiceTile(s)],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _hero() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final titleColor = isDark ? Colors.white : R2VBrand.ink;
    final subColor = isDark ? Colors.white.withOpacity(0.8) : Colors.black87;

    final textCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'R2V TALENT',
          style: TextStyle(
            color: R2VBrand.lilac,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Hire expert\n3D creators.',
          style: TextStyle(
            color: titleColor,
            fontSize: isWeb ? 38 : 28,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Find specialists for modeling, texturing, rigging, animation, '
          'product visualization, game assets, and print-ready cleanup.',
          style: TextStyle(
            color: subColor,
            fontSize: isWeb ? 15 : 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/talent/services'),
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: const Text('Browse Services'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? R2VBrand.purple.withOpacity(0.9)
                    : R2VBrand.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, '/talent/post-project'),
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: const Text('Post a Project'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white : R2VBrand.ink,
                side: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.22)
                      : Colors.black.withOpacity(0.12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, '/talent/become-talent'),
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Become a Talent'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white : R2VBrand.ink,
                side: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.22)
                      : Colors.black.withOpacity(0.12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return R2VGlassCard(
      padding: const EdgeInsets.all(26),
      radius: 26,
      child: isWeb
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: textCol),
                const SizedBox(width: 28),
                Expanded(flex: 4, child: _heroHighlights(isDark)),
              ],
            )
          : textCol,
    );
  }

  Widget _heroHighlights(bool isDark) {
    const items = [
      ['Verified 3D experts', Icons.verified_rounded],
      ['Secure orders & milestones', Icons.lock_clock_rounded],
      ['Built-in chat, files & voice', Icons.forum_rounded],
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.1,
          colors: [
            R2VBrand.purple.withOpacity(0.20),
            R2VBrand.blue.withOpacity(0.08),
            Colors.transparent,
          ],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: R2VBrand.lilac.withOpacity(0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: R2VBrand.lilac.withOpacity(0.5),
                      ),
                    ),
                    child: Icon(
                      it[1] as IconData,
                      size: 18,
                      color: isDark ? Colors.white : R2VBrand.purple,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      it[0] as String,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withOpacity(0.92)
                            : R2VBrand.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _talents() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: _searchBox(
            'Search talents...',
            (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<FreelanceProfile>>(
            future: r2vFreelance.freelancers(search: _search),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const _Loading();
              if (snap.hasError)
                return _Error(
                  snap.error.toString(),
                  onRetry: () => setState(() {}),
                );
              final rows = snap.data ?? const [];
              if (rows.isEmpty)
                return const _Empty('No talents match your filters.');
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: ResponsiveGrid(
                  desktopColumns: 2,
                  children: [for (final t in rows) _TalentTile(t)],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _talentDetail(String id) {
    if (id.isEmpty) return const _Empty('Missing talent id.');
    return FutureBuilder<FreelanceProfile>(
      future: r2vFreelance.freelancer(id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const _Loading();
        if (snap.hasError)
          return _Error(snap.error.toString(), onRetry: () => setState(() {}));
        final t = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _profileHeader(t),
            const SizedBox(height: 18),
            _sectionTitle('Services'),
            if (t.services.isEmpty)
              const _Empty('This talent has not published services yet.')
            else
              ...t.services.map((s) => _ServiceTile(s)),
            const SizedBox(height: 18),
            _sectionTitle('Portfolio'),
            if (t.portfolioLinks.isEmpty)
              const Text('No portfolio links yet.')
            else
              ...t.portfolioLinks.map(
                (p) =>
                    ListTile(leading: const Icon(Icons.link), title: Text(p)),
              ),
          ],
        );
      },
    );
  }

  Widget _profileHeader(FreelanceProfile t) {
    return R2VGlassCard(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: t.avatarUrl?.isNotEmpty == true
                    ? NetworkImage(t.avatarUrl!)
                    : null,
                child: t.avatarUrl?.isNotEmpty == true
                    ? null
                    : Text(t.displayName.isNotEmpty ? t.displayName[0] : '?'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(t.title),
                    Text(
                      '${t.rating.toStringAsFixed(1)} rating • ${t.completedJobs} completed • ${t.availability}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (t.bio?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(t.bio!),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              const _Badge('Verified'),
              if (t.rating >= 4.8) const _Badge('Top Rated'),
              const _Badge('AI 3D Expert'),
              for (final s in t.skills.take(8)) Chip(label: Text(s)),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(
              context,
              '/talent/post-project',
              arguments: {
                'talent_id': t.id,
                'title': 'Custom project for ${t.displayName}',
              },
            ),
            icon: const Icon(Icons.handshake_outlined),
            label: const Text('Hire / request quote'),
          ),
        ],
      ),
    );
  }

  Widget _services() {
    final hasFilters = _search.isNotEmpty || _category != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _searchBox(
                  'Search services...',
                  (v) {
                    _search = v.trim();
                    _reloadServices();
                  },
                  controller: _serviceSearchController,
                  onClear: _search.isEmpty
                      ? null
                      : () {
                          _serviceSearchController.clear();
                          _search = '';
                          _reloadServices();
                        },
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: IconButton(
                  tooltip: 'Refresh',
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  onPressed: _reloadServices,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildFilterChip(
                'All',
                _category == null,
                () {
                  if (_category == null) return;
                  setState(() => _category = null);
                  _reloadServices();
                },
              ),
              for (final c in _categories)
                _buildFilterChip(
                  c,
                  _category == c,
                  () {
                    setState(() => _category = (_category == c) ? null : c);
                    _reloadServices();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<FlService>>(
            future: _loadServices(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _Loading();
              }
              if (snap.hasError) {
                return _Error(snap.error.toString(), onRetry: _reloadServices);
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                if (hasFilters) {
                  return R2VEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No services match your filters',
                    message: 'Try a different search term or category.',
                    primaryLabel: 'Clear filters',
                    onPrimary: () {
                      _serviceSearchController.clear();
                      _search = '';
                      setState(() => _category = null);
                      _reloadServices();
                    },
                  );
                }
                return R2VEmptyState(
                  icon: Icons.storefront_rounded,
                  title: 'No active services yet',
                  message:
                      'Post a project and let expert 3D talents come to you, '
                      'or apply to start offering your own services.',
                  primaryLabel: 'Post a Project',
                  onPrimary: () =>
                      Navigator.pushNamed(context, '/talent/post-project'),
                  secondaryLabel: 'Become a Talent',
                  onSecondary: () =>
                      Navigator.pushNamed(context, '/talent/become-talent'),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reloadServices(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  child: ResponsiveGrid(
                    desktopColumns: 3,
                    children: [for (final s in rows) _ServiceTile(s)],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _serviceDetail(String id) {
    if (id.isEmpty) return const _Empty('Missing service id.');
    return FutureBuilder<FlService>(
      future: r2vFreelance.service(id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const _Loading();
        if (snap.hasError)
          return _Error(snap.error.toString(), onRetry: () => setState(() {}));
        final s = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _ServiceTile(s, expanded: true),
            const SizedBox(height: 12),
            _OrderForm(service: s),
          ],
        );
      },
    );
  }

  Widget _postProject() => ListView(
    padding: const EdgeInsets.all(18),
    children: [_OrderForm(prefill: widget.prefill)],
  );
  Widget _buildActionGlassChip(String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Using a bright blue/cyan to match your screenshot, 
    // or you can switch this back to R2VBrand.purple
    const activeColor = R2VBrand.purple; // Bright blue/cyan color for active state

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.5)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                const Icon(Icons.check_rounded, size: 16, color: Colors.black87),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.black87 // Dark text on the bright active pill
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orders() {
    return FutureBuilder<List<FlOrder>>(
      future: r2vFreelance.orders(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const _Loading();
        if (snap.hasError)
          return _Error(snap.error.toString(), onRetry: () => setState(() {}));
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return R2VEmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'No talent orders yet',
            message:
                'When you hire a talent or place an order, it will appear '
                'here so you can track delivery, revisions and messages.',
            primaryLabel: 'Browse Services',
            onPrimary: () => Navigator.pushNamed(context, '/talent/services'),
            secondaryLabel: 'Post a Project',
            onSecondary: () =>
                Navigator.pushNamed(context, '/talent/post-project'),
          );
        }
        return DefaultTabController(
          length: 6,
          child: Column(
            children: [
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Pending'),
                  Tab(text: 'Active'),
                  Tab(text: 'Delivered'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Cancelled'),
                  Tab(text: 'Disputed'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _orderList(
                      rows.where((o) => o.status == 'pending').toList(),
                    ),
                    _orderList(
                      rows
                          .where(
                            (o) => [
                              'accepted',
                              'in_progress',
                              'revision_requested',
                            ].contains(o.status),
                          )
                          .toList(),
                    ),
                    _orderList(
                      rows.where((o) => o.status == 'delivered').toList(),
                    ),
                    _orderList(
                      rows.where((o) => o.status == 'completed').toList(),
                    ),
                    _orderList(
                      rows
                          .where(
                            (o) => ['cancelled', 'rejected'].contains(o.status),
                          )
                          .toList(),
                    ),
                    _orderList(
                      rows.where((o) => o.status == 'disputed').toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _orderList(List<FlOrder> rows) {
    if (rows.isEmpty) return const _Empty('Nothing here yet.');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: ResponsiveGrid(
        desktopColumns: 2,
        children: [for (final o in rows) _OrderTile(o)],
      ),
    );
  }

  Widget _orderDetail(String id) {
    if (id.isEmpty) return const _Empty('Missing order id.');
    return FutureBuilder<FlOrder>(
      future: r2vFreelance.order(id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const _Loading();
        if (snap.hasError)
          return _Error(snap.error.toString(), onRetry: () => setState(() {}));
        final o = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _OrderTile(o, expanded: true),
            const SizedBox(height: 12),
            _OrderActions(order: o, onChanged: () => setState(() {})),
            const SizedBox(height: 12),
            _OrderChat(orderId: o.id),
          ],
        );
      },
    );
  }

  Widget _chat(String id) => id.isEmpty
      ? const _Empty('Missing order id.')
      : _OrderChat(orderId: id, fullPage: true);

  Widget _apply() => const _ApplyForm();

  Widget _dashboard() {
    return FutureBuilder<FlDashboard>(
      future: r2vFreelance.dashboardSummary(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const _Loading();
        if (snap.hasError)
          return _Error(snap.error.toString(), onRetry: () => setState(() {}));
        final d = snap.data!;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (!d.isFreelancer) ...[
              R2VEmptyState(
                icon: Icons.workspace_premium_rounded,
                title: 'Start offering your talent on R2V',
                message:
                    'Apply to become a verified R2V talent and sell professional '
                    '3D services — modeling, texturing, rigging, animation, product '
                    'visualization and print-ready cleanup.',
                primaryLabel: 'Apply to become a Talent',
                onPrimary: () =>
                    Navigator.pushNamed(context, '/talent/become-talent'),
                secondaryLabel: 'Browse Services',
                onSecondary: () =>
                    Navigator.pushNamed(context, '/talent/services'),
              ),
              const SizedBox(height: 18),
            ],

            Text(
              'Dashboard Overview',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),

            // Hero Earnings & Rating Card
            _buildEarningsHero(d, context),
            const SizedBox(height: 18),

            // Stats Grid
            ResponsiveGrid(
              desktopColumns: 4,
              children: [
                _StatCard(
                  'Incoming Orders',
                  '${d.incomingOrders}',
                  Icons.move_to_inbox_rounded,
                ),
                _StatCard(
                  'Active Work',
                  '${d.activeOrders}',
                  Icons.autorenew_rounded,
                ),
                _StatCard(
                  'Completed Jobs',
                  '${d.completedJobs}',
                  Icons.check_circle_outline_rounded,
                ),
                _StatCard(
                  'Active Services',
                  '${d.serviceCount}',
                  Icons.grid_view_rounded,
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (d.isFreelancer) ...[
              Text(
                'Profile & Availability',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (d.profile != null) _ProfileEditor(profile: d.profile!),

              const SizedBox(height: 24),
              Text(
                'Publish New Service',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const _ServiceEditor(),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEarningsHero(FlDashboard d, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return R2VGlassCard(
      padding: const EdgeInsets.all(24),
      radius: 24,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [
              R2VBrand.purple.withOpacity(isDark ? 0.35 : 0.15),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Earnings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : Colors.black54,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\$${d.earnings.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : R2VBrand.ink,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Icon(Icons.star_rounded, color: AppColors.star, size: 36),
                const SizedBox(height: 4),
                Text(
                  d.rating == 0 ? 'New' : d.rating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : R2VBrand.ink,
                  ),
                ),
                Text(
                  'Average Rating',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBox(
    String hint,
    ValueChanged<String> onSubmitted, {
    TextEditingController? controller,
    VoidCallback? onClear,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontSize: 15,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    size: 18,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  onPressed: onClear,
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: controller == null ? (v) => setState(() => _search = v) : null,
        onSubmitted: onSubmitted,
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _TalentTile extends StatelessWidget {
  const _TalentTile(this.t);
  final FreelanceProfile t;
  @override
  Widget build(BuildContext context) {
    return R2VGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      radius: 20,
      hoverLift: true,
      onTap: () => Navigator.pushNamed(context, '/talent/talents/${t.id}'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: CircleAvatar(
          backgroundColor: R2VBrand.lilac.withValues(alpha: 0.2),
          backgroundImage: t.avatarUrl?.isNotEmpty == true
              ? NetworkImage(t.avatarUrl!)
              : null,
          child: t.avatarUrl?.isNotEmpty == true
              ? null
              : Text(t.displayName.isNotEmpty ? t.displayName[0] : '?'),
        ),
        title: Text(
          t.displayName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${t.title} • ${t.rating.toStringAsFixed(1)} • ${t.availability}',
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile(this.s, {this.expanded = false});
  final FlService s;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    return R2VGlassCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      hoverLift: !expanded,
      onTap: expanded
          ? null
          : () => Navigator.pushNamed(context, '/talent/services/${s.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _Badge('\$${s.startingPrice.toStringAsFixed(0)}+'),
            ],
          ),
          if (s.freelancer != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    s.freelancer!.displayName,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (s.freelancer!.rating > 0) ...[
                  const Icon(Icons.star, size: 14, color: AppColors.star),
                  const SizedBox(width: 2),
                  Text(
                    s.freelancer!.rating.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            s.description,
            maxLines: expanded ? 12 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _Badge(s.category),
              _Badge('${s.deliveryDays} days'),
              _Badge('${s.revisions} revisions'),
              if (s.deliveryDays <= 3) const _Badge('Fast Delivery'),
            ],
          ),
          if (!expanded) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/talent/services/${s.id}'),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View Details'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Backend order statuses are the source of truth (ORDER_STATUSES).
const Map<String, String> _orderStatusLabels = {
  'pending': 'Pending',
  'accepted': 'Accepted',
  'rejected': 'Rejected',
  'in_progress': 'In Progress',
  'delivered': 'Delivered',
  'revision_requested': 'Revision Requested',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
  'disputed': 'Disputed',
};

String _orderStatusLabel(String status) => _orderStatusLabels[status] ?? status;

// Order status pill delegates to the shared, color-coded StatusPill
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;
  @override
  Widget build(BuildContext context) =>
      StatusPill(status, label: _orderStatusLabel(status));
}

class _OrderTile extends StatelessWidget {
  const _OrderTile(this.o, {this.expanded = false});
  final FlOrder o;
  final bool expanded;

  String _date(String raw) => raw.isNotEmpty ? raw.split('T').first : '—';

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return R2VGlassCard(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        hoverLift: true,
        onTap: () => Navigator.pushNamed(context, '/talent/orders/${o.id}'),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            o.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${o.freelancer?.displayName ?? 'Talent'} • \$${o.budget.toStringAsFixed(0)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _StatusPill(o.status),
        ),
      );
    }
    return R2VGlassCard(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  o.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              _StatusPill(o.status),
            ],
          ),
          if (o.service != null) ...[
            const SizedBox(height: 4),
            Text(
              'Service: ${o.service!.title}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Meta('Client', o.client?.name ?? '—'),
              _Meta('Talent', o.freelancer?.displayName ?? '—'),
              _Meta('Budget', '\$${o.budget.toStringAsFixed(0)}'),
              if (o.deadline != null && o.deadline!.isNotEmpty)
                _Meta('Deadline', _date(o.deadline!)),
              _Meta('Created', _date(o.createdAt)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Requirements', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            o.requirements.isNotEmpty
                ? o.requirements
                : 'No requirements provided.',
          ),
          if (o.revisionNote != null && o.revisionNote!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Revision note',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(o.revisionNote!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _OrderForm extends StatefulWidget {
  const _OrderForm({this.service, this.prefill});
  final FlService? service;
  final Map<String, dynamic>? prefill;
  @override
  State<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<_OrderForm> {
  final _title = TextEditingController();
  final _requirements = TextEditingController();
  final _budget = TextEditingController();
  final _attachments = TextEditingController();
  String? _talentId;
  DateTime? _deadline;
  bool _saving = false;

  bool _loadingTalents = false;
  String? _talentsError;
  List<FreelanceProfile> _talents = const [];

  bool get _serviceMode => widget.service != null;

  @override
  void initState() {
    super.initState();
    _title.text =
        widget.prefill?['title']?.toString() ?? widget.service?.title ?? '';
    _budget.text = widget.service?.startingPrice.toStringAsFixed(0) ?? '';
    _talentId =
        widget.prefill?['talent_id']?.toString() ??
        widget.prefill?['freelancer_id']?.toString();
    final attachments = widget.prefill?['attachments'];
    if (attachments is List) {
      _attachments.text = attachments.map((e) => e.toString()).join(', ');
    }
    if (!_serviceMode) _loadTalents();
  }

  @override
  void dispose() {
    _title.dispose();
    _requirements.dispose();
    _budget.dispose();
    _attachments.dispose();
    super.dispose();
  }

  Future<void> _loadTalents() async {
    setState(() {
      _loadingTalents = true;
      _talentsError = null;
    });
    try {
      final rows = await r2vFreelance.freelancers();
      if (!mounted) return;
      setState(() {
        _talents = rows;
        if (_talentId != null && !rows.any((t) => t.id == _talentId)) {
          _talentId = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _talentsError = e is ApiException
              ? e.message
              : 'Could not load talents.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTalents = false);
    }
  }

  InputDecoration _glassDecoration(BuildContext context, String hint, {bool isMultiline = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white70 : Colors.black54,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: isMultiline ? 24 : 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: R2VBrand.lilac.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return R2VGlassCard(
      padding: EdgeInsets.zero,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create project order',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : R2VBrand.ink,
                  ),
            ),
            const SizedBox(height: 16),
            _contextHeader(context),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: _glassDecoration(context, 'Project title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _requirements,
              minLines: 4,
              maxLines: 8,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: _glassDecoration(context, 'Requirements / description', isMultiline: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _budget,
              keyboardType: TextInputType.number,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: _glassDecoration(context, 'Budget (USD)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _deadline == null
                        ? 'No deadline set'
                        : 'Deadline: ${_deadline!.toIso8601String().split('T').first}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickDeadline,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(
                    _deadline == null ? 'Set deadline' : 'Change',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: R2VBrand.lilac,
                  ),
                ),
                if (_deadline != null)
                  IconButton(
                    tooltip: 'Clear deadline',
                    icon: const Icon(Icons.clear, size: 18),
                    color: Theme.of(context).colorScheme.error,
                    onPressed: () => setState(() => _deadline = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _attachments,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: _glassDecoration(context, 'Attachment URLs or model keys, comma separated'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _saving ? 'Creating...' : 'Create Order',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: R2VBrand.purple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contextHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_serviceMode) {
      final s = widget.service!;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 4),
            Text(
              'Talent: ${s.freelancer?.displayName ?? 'Selected talent'} • Starting at \$${s.startingPrice.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }
    if (_loadingTalents) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(
          color: R2VBrand.lilac,
          backgroundColor: isDark ? Colors.white10 : Colors.black12,
        ),
      );
    }
    if (_talentsError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _talentsError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(onPressed: _loadTalents, child: const Text('Retry')),
        ],
      );
    }
    if (_talents.isEmpty) {
      return Text(
        'No approved talents are available to order from yet.',
        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
      );
    }
    return DropdownButtonFormField<String>(
      value: _talentId,
      isExpanded: true,
      dropdownColor: isDark ? R2VBrand.bgDark : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: _glassDecoration(context, 'Choose a talent'),
      icon: Icon(Icons.expand_more_rounded, color: isDark ? Colors.white70 : Colors.black54),
      items: [
        for (final t in _talents)
          DropdownMenuItem(
            value: t.id,
            child: Text(
              '${t.displayName} — ${t.title}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => setState(() => _talentId = v),
    );
  }

Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            // 1. Override the primary colors to match your brand
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: R2VBrand.lilac,
                    onPrimary: Colors.white,
                    surface: const Color(0xFF1A1A24), // Sleek deep background
                    onSurface: Colors.white,
                  )
                : ColorScheme.light(
                    primary: R2VBrand.purple,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ),
            // 2. Customize the DatePicker specifically
            datePickerTheme: DatePickerThemeData(
              backgroundColor: isDark
                  ? const Color(0xFF1E1E2A).withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.9),
              headerBackgroundColor: Colors.transparent,
              headerForegroundColor: isDark ? Colors.white : R2VBrand.ink,
              dividerColor: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
              // High border radius for the modern look + subtle glass border
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1.5,
                ),
              ),
              dayStyle: const TextStyle(fontWeight: FontWeight.w600),
              yearStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            // 3. Style the "Cancel" and "OK" buttons
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: isDark ? R2VBrand.lilac : R2VBrand.purple,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          // 4. Wrap the dialog in a BackdropFilter for the glassmorphism blur
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: child!,
          ),
        );
      },
    );
    
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty || _requirements.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a title and at least 10 characters of requirements.',
          ),
        ),
      );
      return;
    }
    if (!_serviceMode && (_talentId == null || _talentId!.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please choose a talent.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final order = await r2vFreelance.createOrder({
        'service_id': widget.service?.id,
        'freelancer_id': _serviceMode ? null : _talentId,
        'title': _title.text.trim(),
        'requirements': _requirements.text.trim(),
        'budget':
            double.tryParse(_budget.text) ?? widget.service?.startingPrice ?? 0,
        'deadline': _deadline?.toIso8601String(),
        'attachments': _attachments.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Order created.')));
      Navigator.pushReplacementNamed(context, '/talent/orders/${order.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException
                  ? e.message
                  : 'Could not create order. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _OrderActions extends StatefulWidget {
  const _OrderActions({required this.order, required this.onChanged});
  final FlOrder order;
  final VoidCallback onChanged;
  @override
  State<_OrderActions> createState() => _OrderActionsState();
}

class _OrderActionsState extends State<_OrderActions> {
  bool _busy = false;
  FlOrder get order => widget.order;

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException
                  ? e.message
                  : 'Action failed. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    String message,
    String confirmLabel,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    String confirmLabel = 'Submit',
    int minLength = 0,
    int maxLines = 4,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final value = controller.text.trim();
          final valid = value.length >= minLength;
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: maxLines,
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(
                labelText: label,
                helperText: minLength > 0
                    ? 'At least $minLength characters'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, value) : null,
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<({String? message, List<String> files})?> _deliveryDialog() {
    final message = TextEditingController();
    final files = TextEditingController();
    return showDialog<({String? message, List<String> files})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: message,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Message to the client',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: files,
              decoration: const InputDecoration(
                labelText: 'Delivery file URLs / keys, comma separated',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final msg = message.text.trim();
              final list = files.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              Navigator.pop(ctx, (
                message: msg.isEmpty ? null : msg,
                files: list,
              ));
            },
            child: const Text('Submit delivery'),
          ),
        ],
      ),
    );
  }

  Future<({int? rating, String? comment})?> _reviewDialog({
    required bool ratingRequired,
  }) {
    int rating = 5;
    bool rated = !ratingRequired ? false : true;
    final comment = TextEditingController();
    return showDialog<({int? rating, String? comment})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(ratingRequired ? 'Leave a review' : 'Accept delivery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ratingRequired
                    ? 'Rate this talent'
                    : 'Optionally rate this talent',
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        (rated && i <= rating) ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                      onPressed: () => setLocal(() {
                        rating = i;
                        rated = true;
                      }),
                    ),
                ],
              ),
              TextField(
                controller: comment,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: (ratingRequired && !rated)
                  ? null
                  : () {
                      final c = comment.text.trim();
                      Navigator.pop(ctx, (
                        rating: rated ? rating : null,
                        comment: c.isEmpty ? null : c,
                      ));
                    },
              child: Text(
                ratingRequired ? 'Submit review' : 'Accept & complete',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deliver() async {
    final res = await _deliveryDialog();
    if (res == null) return;
    await _run(
      () => r2vFreelance.deliverOrder(
        order.id,
        message: res.message,
        files: res.files,
      ),
      'Delivery submitted',
    );
  }

  Future<void> _requestRevision() async {
    final note = await _textDialog(
      title: 'Request a revision',
      label: 'What needs to change?',
      confirmLabel: 'Request revision',
      minLength: 2,
    );
    if (note == null) return;
    await _run(
      () => r2vFreelance.requestRevision(order.id, note),
      'Revision requested',
    );
  }

  Future<void> _complete() async {
    final res = await _reviewDialog(ratingRequired: false);
    if (res == null) return;
    await _run(() async {
      await r2vFreelance.completeOrder(order.id);
      if (res.rating != null) {
        await r2vFreelance.reviewOrder(
          order.id,
          rating: res.rating!,
          comment: res.comment,
        );
      }
    }, 'Order completed');
  }

  Future<void> _review() async {
    final res = await _reviewDialog(ratingRequired: true);
    if (res == null || res.rating == null) return;
    await _run(
      () => r2vFreelance.reviewOrder(
        order.id,
        rating: res.rating!,
        comment: res.comment,
      ),
      'Review submitted',
    );
  }

  Future<void> _dispute() async {
    final reason = await _textDialog(
      title: 'Open a dispute',
      label: 'Describe the problem',
      confirmLabel: 'Open dispute',
      minLength: 5,
    );
    if (reason == null) return;
    await _run(
      () => r2vFreelance.disputeOrder(order.id, reason),
      'Dispute opened',
    );
  }

  Future<void> _accept() async {
    if (!await _confirm(
      'Accept order',
      'Accept this order and start working on it?',
      'Accept',
    ))
      return;
    await _run(() => r2vFreelance.acceptOrder(order.id), 'Order accepted');
  }

  Future<void> _reject() async {
    if (!await _confirm(
      'Reject order',
      'Reject this order? This cannot be undone.',
      'Reject',
    ))
      return;
    await _run(() => r2vFreelance.rejectOrder(order.id), 'Order rejected');
  }

  Future<void> _cancel() async {
    if (!await _confirm(
      'Cancel order',
      'Cancel this order? This cannot be undone.',
      'Cancel order',
    ))
      return;
    await _run(() => r2vFreelance.cancelOrder(order.id), 'Order cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final isTalent =
        order.isFreelancer; // Keeping backend property mapped cleanly
    final isClient = order.isClient;
    final status = order.status;
    final deliverable = [
      'accepted',
      'in_progress',
      'revision_requested',
    ].contains(status);
    final canDispute =
        isClient &&
        [
          'delivered',
          'revision_requested',
          'in_progress',
          'accepted',
        ].contains(status);
    final canCancel =
        isClient && ['pending', 'accepted', 'in_progress'].contains(status);

    final buttons = <Widget>[
      if (isTalent && status == 'pending') ...[
        FilledButton(
          onPressed: _busy ? null : _accept,
          child: const Text('Accept'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _reject,
          child: const Text('Reject'),
        ),
      ],
      if (isTalent && deliverable)
        FilledButton(
          onPressed: _busy ? null : _deliver,
          child: const Text('Submit Delivery'),
        ),
      if (isClient && status == 'delivered') ...[
        FilledButton(
          onPressed: _busy ? null : _complete,
          child: const Text('Accept Delivery'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _requestRevision,
          child: const Text('Request Revision'),
        ),
      ],
      if (order.canReview)
        FilledButton(
          onPressed: _busy ? null : _review,
          child: const Text('Leave Review'),
        ),
      if (canDispute)
        OutlinedButton(
          onPressed: _busy ? null : _dispute,
          child: const Text('Open Dispute'),
        ),
      if (canCancel)
        TextButton(
          onPressed: _busy ? null : _cancel,
          child: const Text('Cancel Order'),
        ),
    ];

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _OrderChat extends StatefulWidget {
  const _OrderChat({required this.orderId, this.fullPage = false});
  final String orderId;
  final bool fullPage;
  @override
  State<_OrderChat> createState() => _OrderChatState();
}

class _OrderChatState extends State<_OrderChat> {
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  late Future<List<FlMessage>> _future;
  bool _sending = false;
  bool _recording = false;
  int _elapsed = 0;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _future = r2vFreelance.messages(widget.orderId);
  }

  @override
  void dispose() {
    _text.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = r2vFreelance.messages(widget.orderId));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await r2vFreelance.sendMessage(orderId: widget.orderId, text: text);
      _text.clear();
      _reload();
    } catch (e) {
      _toast(e is ApiException ? e.message : 'Could not send message');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_sending || _recording) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        _toast('Could not read file');
        return;
      }
      if (bytes.length > 25 * 1024 * 1024) {
        _toast('File too large (max 25 MB)');
        return;
      }
      setState(() => _sending = true);
      await r2vFreelance.uploadMessageAttachment(
        orderId: widget.orderId,
        fileBytes: bytes,
        fileName: f.name,
      );
      _reload();
    } catch (e) {
      _toast(e is ApiException ? e.message : 'Could not send attachment');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (_sending || _recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _toast('Microphone permission denied');
        return;
      }
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(const RecordConfig(), path: path);
      setState(() {
        _recording = true;
        _elapsed = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += 1);
        if (_elapsed >= 300) _stopAndSendVoice();
      });
    } catch (e) {
      _toast('Recording not supported on this device');
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    setState(() {
      _recording = false;
      _sending = true;
    });
    try {
      final uri = await _recorder.stop();
      if (uri == null || uri.isEmpty) {
        _toast('Nothing recorded');
        return;
      }
      final bytes = await readRecordingBytes(uri);
      if (bytes.isEmpty) {
        _toast('Empty recording');
        return;
      }
      final name = kIsWeb ? 'voice_note.webm' : 'voice_note.m4a';
      final mime = kIsWeb ? 'audio/webm' : 'audio/mp4';
      await r2vFreelance.uploadMessageAttachment(
        orderId: widget.orderId,
        fileBytes: bytes,
        fileName: name,
        contentType: mime,
        voice: true,
      );
      _reload();
    } catch (e) {
      _toast(e is ApiException ? e.message : 'Could not send voice note');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<FlMessage>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const _Loading();
        if (snap.hasError) {
          return _Error(
            snap.error is ApiException
                ? (snap.error as ApiException).message
                : 'Could not load messages.',
            onRetry: _reload,
          );
        }
        final rows = snap.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isEmpty)
              const _Empty('No messages yet. Start the conversation.'),
            for (final m in rows) _ChatBubble(message: m),
            const SizedBox(height: 8),
            _recording ? _recordingBar() : _inputRow(),
          ],
        );
      },
    );
    return widget.fullPage
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(child: body),
          )
        : R2VGlassCard(
            radius: 22,
            padding: const EdgeInsets.all(14),
            child: body,
          );
  }

  Widget _inputRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Attach file',
            icon: const Icon(Icons.attach_file),
            onPressed: _sending ? null : _pickAndSendFile,
          ),
          IconButton(
            tooltip: 'Record voice note',
            icon: const Icon(Icons.mic_none),
            onPressed: _sending ? null : _startRecording,
          ),
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Message this order...',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          IconButton(
            color: Theme.of(context).colorScheme.primary,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            onPressed: _sending ? null : _sendText,
          ),
        ],
      ),
    );
  }

  Widget _recordingBar() {
    final mm = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final ss = (_elapsed % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
        const SizedBox(width: 8),
        Text('Recording  $mm:$ss'),
        const Spacer(),
        TextButton(onPressed: _cancelRecording, child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _stopAndSendVoice,
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Send'),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final FlMessage message;

  String _time(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final color = mine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final sender = mine ? 'You' : (message.sender?.name ?? 'User');
    final isVoice =
        message.voiceNoteUrl != null && message.voiceNoteUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            sender,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(mine ? 14 : 4),
                bottomRight: Radius.circular(mine ? 4 : 14),
              ),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.body.isNotEmpty) Text(message.body),
                if (isVoice)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _VoiceNotePlayer(url: message.voiceNoteUrl!),
                  )
                else
                  for (final att in message.attachments)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _attachmentWidget(att),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _time(message.createdAt),
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentWidget(Map<String, dynamic> att) {
    final type = (att['attachment_type'] ?? att['mime_type'] ?? '').toString();
    final url = (att['url'] ?? '').toString();
    if (type.contains('audio') && url.isNotEmpty) {
      return _VoiceNotePlayer(url: url);
    }
    return _ChatAttachmentCard(att: att);
  }
}

class _ChatAttachmentCard extends StatelessWidget {
  const _ChatAttachmentCard({required this.att});
  final Map<String, dynamic> att;

  String get _url => (att['url'] ?? '').toString();
  String get _name =>
      (att['file_name'] ?? att['fileName'] ?? 'attachment').toString();
  String get _type =>
      (att['attachment_type'] ?? att['mime_type'] ?? '').toString();

  Future<void> _open(BuildContext context) async {
    if (_url.isEmpty) return;
    final ok = await launchUrl(
      Uri.parse(_url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open attachment')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _type.contains('image');
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isImage && _url.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _url,
                  width: 200,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(_name, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.download_rounded, size: 16),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceNotePlayer extends StatefulWidget {
  const _VoiceNotePlayer({required this.url});
  final String url;
  @override
  State<_VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<_VoiceNotePlayer> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice note')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: _playing ? 'Pause' : 'Play voice note',
            color: theme.colorScheme.primary,
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 28,
            ),
            onPressed: _toggle,
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.graphic_eq_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          const Text('Voice note'),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _ApplyForm extends StatefulWidget {
  const _ApplyForm();
  @override
  State<_ApplyForm> createState() => _ApplyFormState();
}

class _ApplyFormState extends State<_ApplyForm> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _skills = TextEditingController();
  final _experience = TextEditingController();
  final _portfolio = TextEditingController();
  final _price = TextEditingController();
  bool _saving = false;
  bool _reapply = false;
  late Future<FreelancerApplication?> _future;

  @override
  void initState() {
    super.initState();
    _future = r2vFreelance.myApplication();
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _skills.dispose();
    _experience.dispose();
    _portfolio.dispose();
    _price.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = r2vFreelance.myApplication());
  }

  List<String> _splitCsv(String raw) =>
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FreelancerApplication?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        if (snap.hasError) {
          return _Error(snap.error.toString(), onRetry: _reload);
        }
        final app = snap.data;
        final showForm = app == null || (app.status == 'rejected' && _reapply);
        if (!showForm) {
          return _StatusView(
            app: app,
            onReapply: () => setState(() => _reapply = true),
          );
        }
        return _buildForm(context, previous: app);
      },
    );
  }

  Widget _buildForm(BuildContext context, {FreelancerApplication? previous}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    InputDecoration glassDecoration(String hint, {bool isMultiline = false}) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: isMultiline ? 24 : 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: R2VBrand.lilac.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        Text(
          'Become a talent',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : R2VBrand.ink,
              ),
        ),
        const SizedBox(height: 24),
        if (previous != null &&
            previous.status == 'rejected' &&
            previous.adminNote?.isNotEmpty == true) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .error
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Previous application feedback',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          )),
                      const SizedBox(height: 4),
                      Text(previous.adminNote!,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        TextField(
          controller: _name,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: glassDecoration('Full name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: glassDecoration('Professional title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _skills,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: glassDecoration('Skills, comma separated'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _experience,
          minLines: 4,
          maxLines: 8,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: glassDecoration('Experience', isMultiline: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _portfolio,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: glassDecoration('Portfolio links, comma separated'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _price,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: glassDecoration('Expected price range'),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: R2VBrand.purple, 
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Submit application',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty || _title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name and professional title.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await r2vFreelance.apply(
        fullName: _name.text.trim(),
        title: _title.text.trim(),
        skills: _splitCsv(_skills.text),
        experience: _experience.text.trim().isEmpty
            ? null
            : _experience.text.trim(),
        portfolioLinks: _splitCsv(_portfolio.text),
        expectedPriceRange: _price.text.trim().isEmpty
            ? null
            : _price.text.trim(),
      );
      if (!mounted) return;
      _reapply = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Application submitted. It is now under review.'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : 'Could not submit application. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.app, required this.onReapply});
  final FreelancerApplication app;
  final VoidCallback onReapply;

  static const _labels = {
    'pending_review': 'Pending Review',
    'approved': 'Approved',
    'rejected': 'Rejected',
    'needs_more_info': 'Needs More Info',
  };

  static const _messages = {
    'pending_review':
        'Your application is under review. We will notify you once an admin makes a decision.',
    'approved':
        "You're an approved talent. You can now manage your services and availability from the dashboard.",
    'rejected':
        'Your application was not approved. You may review the feedback below and submit a new application.',
    'needs_more_info':
        'An admin requested more information about your application. Please review the note below.',
  };

  Color _color(BuildContext context) {
    switch (app.status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Theme.of(context).colorScheme.error;
      case 'needs_more_info':
        return Colors.blue;
      case 'pending_review':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Text(
              'Your application',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Spacer(),
            Chip(
              label: Text(
                _labels[app.status] ?? app.status,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              backgroundColor: color.withValues(alpha: 0.12),
              side: BorderSide(color: color.withValues(alpha: 0.4)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        R2VGlassCard(
          padding: EdgeInsets.zero,
          radius: 22,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (app.title.isNotEmpty)
                  Text(
                    app.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const SizedBox(height: 6),
                Text(
                  _messages[app.status] ?? 'Application status: ${app.status}',
                ),
                if (app.adminNote?.isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Admin note',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(app.adminNote!),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (app.status == 'approved')
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/talent/dashboard'),
            icon: const Icon(Icons.dashboard_outlined),
            label: const Text('Go to talent dashboard'),
          ),
        if (app.status == 'rejected')
          FilledButton.icon(
            onPressed: onReapply,
            icon: const Icon(Icons.refresh),
            label: const Text('Submit a new application'),
          ),
      ],
    );
  }
}

class _ProfileEditor extends StatelessWidget {
  const _ProfileEditor({required this.profile});
  final FreelanceProfile profile;

  @override
  Widget build(BuildContext context) {
    return R2VGlassCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  profile.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Current Availability:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: R2VBrand.lilac.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: R2VBrand.lilac.withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: profile.availability.toLowerCase(),
                    isDense: true,
                    icon: const Icon(Icons.expand_more_rounded, size: 20),
                    onChanged: (v) {
                      if (v != null) r2vFreelance.updateAvailability(v);
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'available',
                        child: Text('Available'),
                      ),
                      DropdownMenuItem(value: 'busy', child: Text('Busy')),
                      DropdownMenuItem(
                        value: 'offline',
                        child: Text('Offline'),
                      ),
                      DropdownMenuItem(
                        value: 'not_accepting_work',
                        child: Text('Not accepting work'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceEditor extends StatefulWidget {
  const _ServiceEditor();
  @override
  State<_ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends State<_ServiceEditor> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  String _category = _categories.first;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    return R2VGlassCard(
      padding: EdgeInsets.zero,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Service Title'),
            ),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            DropdownButtonFormField(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Starting price (\$USD)',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _creating ? null : _create,
              icon: const Icon(Icons.publish_rounded, size: 18),
              label: _creating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publish Service'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await r2vFreelance.createService({
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'category': _category,
        'starting_price': double.tryParse(_price.text) ?? 0,
        'delivery_days': 7,
        'revisions': 2,
        'file_formats': ['glb', 'obj', 'fbx', 'blend'],
        'status': 'active',
      });
      if (!mounted) return;
      _title.clear();
      _description.clear();
      _price.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Service created')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : 'Could not create service. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return R2VGlassCard(
      radius: 20,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: R2VBrand.lilac.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: R2VBrand.lilac, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Chip(label: Text(text), visualDensity: VisualDensity.compact);
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppLoading();
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      R2VEmptyState(icon: Icons.inbox_rounded, title: text);
}

class _Error extends StatelessWidget {
  const _Error(this.text, {required this.onRetry});
  final String text;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) =>
      AppErrorState(message: text, onRetry: onRetry);
}
