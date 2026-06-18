// home_screen.dart
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../api/r2v_api.dart';
import '../api/api_exception.dart';
import '../main.dart'; // Needed for themeNotifier
import 'widgets/r2v_section_nav.dart'; // shared LumaBar glass bottom nav
import 'widgets/r2v_top_nav_tabs.dart'; // shared desktop top-nav tab strip
import 'widgets/r2v_notification_bell.dart';

/// model_viewer_plus renders inside an HtmlElementView whose <model-viewer src>
/// resolves relative to the page root ("/"), while Flutter serves declared
/// assets under "/assets/<key>". So an asset key like "assets/models/X.glb"
/// must be requested as "assets/assets/models/X.glb". This helper adds that
/// prefix. Use ONLY for ModelViewer src/poster, never for Image.asset.
String _mvUrl(String assetKey) => 'assets/$assetKey';

class MarketModel {
  final String name;
  final String author;
  final String description;
  final List<String> tags;
  final String likes;
  final String tagLabel;
  final String glbAssetPath;
  final String posterAssetPath;

  const MarketModel({
    required this.name,
    required this.author,
    required this.description,
    required this.tags,
    required this.likes,
    required this.tagLabel,
    required this.glbAssetPath,
    required this.posterAssetPath,
  });
}

class HeroModel {
  final String src;
  final String prompt;

  const HeroModel({
    required this.src,
    required this.prompt,
  });
}

class HomeScreen extends StatefulWidget {
  final String username;

  const HomeScreen({super.key, this.username = 'User'});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  final int _webActiveNavIndex = 0;

  late final ScrollController _scrollController;
  bool _collapsed = false;

  int _selectedUseCase = 0;
  Timer? _useCaseAutoTimer;
  bool _pauseUseCaseAutoScroll = false;

  bool _lastIsWeb = false;

  MarketModel? _activeMarketModel;

  bool _loadingSummary = false;
  String _displayName = '';

  Map<String, dynamic> _continueAI = {
    "title": "Neon sci-fi car in rainy alley",
    "subtitle": "Last prompt • 2 hours ago",
    "route": "/aichat",
    "accent": const Color(0xFF8A4FFF),
    "icon": Icons.bolt_rounded,
  };

  Map<String, dynamic> _continueScan = {
    "title": "Vintage Chair Scan",
    "subtitle": "Draft scan • 10 minutes ago",
    "route": "/photo_scan",
    "accent": const Color(0xFFF72585),
    "icon": Icons.photo_camera_rounded,
  };

  Map<String, dynamic> _continueMarket = {
    "title": "Porsche 911 Asset",
    "subtitle": "Last viewed • yesterday",
    "route": "/explore",
    "accent": const Color(0xFF4895EF),
    "icon": Icons.storefront_rounded,
  };

  Map<String, int> _stats = {
    "Models": 12,
    "Scans": 5,
    "Downloads": 9,
  };

  final List<Map<String, String>> _useCases = const [
    {"id": "film", "title": "Film Production", "asset": "assets/usecases/film.png"},
    {"id": "product", "title": "Product Design", "asset": "assets/usecases/product.png"},
    {"id": "edu", "title": "Education", "asset": "assets/usecases/education.png"},
    {"id": "game", "title": "Game\nDevelopment", "asset": "assets/usecases/game.png"},
    {"id": "print", "title": "3D Printing", "asset": "assets/usecases/printing.png"},
    {"id": "vr", "title": "VR/AR", "asset": "assets/usecases/vr.png"},
    {"id": "interior", "title": "Interior Design", "asset": "assets/usecases/interior.png"},
  ];

  final List<Map<String, dynamic>> _useCaseDetails = const [
    {
      "id": "film",
      "title": "Film Production",
      "subtitle": "Cut costs and accelerate VFX and previs workflows with R2V AI",
      "bullets": ["Fast Previs & Look Dev", "Streamlined VFX Workflow", "Industry-Standard Quality"],
      "cta": "Explore More",
      "ctaRoute": "/explore",
      "preview": "assets/usecase_previews/film.png",
      "accent": Color(0xFF9CA3AF),
    },
    {
      "id": "product",
      "title": "Product Design",
      "subtitle": "Prototype faster with AI-assisted 3D concepts and ready assets.",
      "bullets": ["Rapid Ideation", "Accurate Scale Mockups", "Export-Ready Models"],
      "cta": "Explore More",
      "ctaRoute": "/explore",
      "preview": "assets/usecase_previews/product.png",
      "accent": Color(0xFF38BDF8),
    },
    {
      "id": "edu",
      "title": "Education",
      "subtitle": "Teach 3D concepts interactively with instant models and scans.",
      "bullets": ["Interactive Lessons", "Visual Learning", "Student Projects"],
      "cta": "Explore More",
      "ctaRoute": "/explore",
      "preview": "assets/usecase_previews/education.png",
      "accent": Color(0xFFFDE68A),
    },
    {
      "id": "game",
      "title": "Game Development",
      "subtitle": "Generate and iterate on assets faster for your next game world.",
      "bullets": ["Concept to Asset", "Style Variations", "Faster Iteration"],
      "cta": "Explore More",
      "ctaRoute": "/explore",
      "preview": "assets/usecase_previews/game.png",
      "accent": Color(0xFF22D3EE),
    },
    {
      "id": "print",
      "title": "3D Printing",
      "subtitle": "Scan real objects and convert ideas into printable 3D models.",
      "bullets": ["Scan to STL", "Repair & Optimize", "Print-Ready Output"],
      "cta": "Start Scan",
      "ctaRoute": "/photo_scan",
      "preview": "assets/usecase_previews/printing.png",
      "accent": Color(0xFFA3E635),
    },
    {
      "id": "vr",
      "title": "VR/AR",
      "subtitle": "Build immersive experiences with quick, clean 3D content.",
      "bullets": ["Lightweight Assets", "Realistic Textures", "GLB/FBX Export"],
      "cta": "Explore More",
      "ctaRoute": "/explore",
      "preview": "assets/usecase_previews/vr.png",
      "accent": Color(0xFFC084FC),
    },
    {
      "id": "interior",
      "title": "Interior Design",
      "subtitle": "Create and visualize spaces with furniture and room assets.",
      "bullets": ["Room Mockups", "Asset Library", "Client Presentations"],
      "cta": "Explore More",
      "ctaRoute": "/explore",
      "preview": "assets/usecase_previews/interior.png",
      "accent": Color(0xFFFCA5A5),
    },
  ];

  final List<MarketModel> _models = const [
    MarketModel(
      name: "Porsche 911",
      author: "McLaughlin Rh",
      description: "911 sports car, clean geometry, studio lighting.",
      tags: ["car", "game-ready", "complex", "edges", "symmetric"],
      likes: "1.2k",
      tagLabel: "Saved",
      // NOTE: assets/models/911.glb is missing from the repo. Repointed to an
      // existing car model so the panel renders. Restore 911.glb and revert
      // this line when the real asset is available.
      glbAssetPath: "assets/models/GOLD_KART.glb",
      posterAssetPath: "assets/posters/911.png",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _displayName = widget.username;
    _startUseCaseAutoSwitch();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loadingSummary = true);
    try {
      final profile = await r2vProfile.me();
      final dashboard = await r2vDashboard.me();
      final aiJobs = await r2vAiJobs.listJobs(limit: 1);
      final scanJobs = await r2vScanJobs.listJobs(limit: 1);
      final assets = await r2vMarketplace.listAssets(limit: 1);

      if (!mounted) return;

      setState(() {
        _displayName = profile.username.isNotEmpty ? profile.username : _displayName;
        _stats = {
          "Models": dashboard.assets,
          "Scans": dashboard.scanJobs,
          "Downloads": dashboard.downloads,
        };

        if (aiJobs.isNotEmpty) {
          final job = aiJobs.first;
          _continueAI = {
            "title": job.prompt?.isNotEmpty == true ? job.prompt! : "AI job ${job.id}",
            "subtitle": "Status: ${job.status}",
            "route": "/aichat",
            "accent": const Color(0xFF8A4FFF),
            "icon": Icons.bolt_rounded,
          };
        }

        if (scanJobs.isNotEmpty) {
          final job = scanJobs.first;
          _continueScan = {
            "title": "Scan job ${job.id}",
            "subtitle": "Status: ${job.status}",
            "route": "/photo_scan",
            "accent": const Color(0xFFF72585),
            "icon": Icons.photo_camera_rounded,
          };
        }

        if (assets.isNotEmpty) {
          final asset = assets.first;
          _continueMarket = {
            "title": asset.title,
            "subtitle": asset.category,
            "route": "/explore",
            "accent": const Color(0xFF4895EF),
            "icon": Icons.storefront_rounded,
          };
        }
      });
    } catch (_) {
      // Graceful degradation, continue showing defaults if fetch fails
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final dir = _scrollController.position.userScrollDirection;
    if (dir == ScrollDirection.reverse && !_collapsed) {
      setState(() => _collapsed = true);
    } else if (dir == ScrollDirection.forward && _collapsed) {
      setState(() => _collapsed = false);
    }
  }

  void _startUseCaseAutoSwitch() {
    _useCaseAutoTimer?.cancel();
    _useCaseAutoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (_pauseUseCaseAutoScroll) return;

      if (_lastIsWeb) {
        if (_webActiveNavIndex != 0) return;
      } else {
        if (_selectedTab != 0) return;
      }

      setState(() => _selectedUseCase = (_selectedUseCase + 1) % _useCases.length);
    });
  }

  void _onUseCaseTap(int idx) {
    setState(() => _selectedUseCase = idx);
    setState(() => _pauseUseCaseAutoScroll = true);
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _pauseUseCaseAutoScroll = false);
    });
  }

  @override
  void dispose() {
    _useCaseAutoTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = MediaQuery.of(context).size.width >= 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    _lastIsWeb = isWeb;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0414) : const Color(0xFFF8FAFC),
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(child: MeshyParticleBackground(isDark: isDark)),
          Positioned.fill(child: _ReactHeroBackground(isDark: isDark)),
          Positioned.fill(child: isWeb ? _buildWebHome(context, isDark) : _buildMobileHome(context, isDark)),
          if (_activeMarketModel != null)
            Positioned.fill(
              child: _HomeMarketModelPanel(
                model: _activeMarketModel!,
                onClose: () => setState(() => _activeMarketModel = null),
                isDark: isDark,
              ),
            ),
          // Mobile-only floating LumaBar — placed here in the OUTER Stack
          // (sibling of the background), identical to Settings, so no opaque
          // strip is ever painted behind the pill.
          if (!isWeb && _activeMarketModel == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _GlassBottomNavBar(
                // Home is always the active mobile tab on this screen; tapping
                // any other icon navigates away to its real page.
                currentIndex: 0,
                onTap: (i) {
                  // Direct, app-like mobile navigation: each icon opens its real
                  // page instead of swapping Home's body to an intermediate
                  // shortcut card. Routes mirror the shared R2VSectionNav used on
                  // every other screen, so back/refresh/deep-link stay correct.
                  // (Home shortcut "tabs" are no longer reachable on mobile, so
                  // _buildAiTabMobile/_buildScanTabMobile/etc. never render.)
                  if (i == 0) return; // already on Home
                  Navigator.pushReplacementNamed(context, R2VSectionNav.routes[i]);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebHome(BuildContext context, bool isDark) {
    final double w = MediaQuery.of(context).size.width;
    final double contentWidth = w > 1180 ? 1180 : w;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildWebTopBar(context, isDark),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center, // Centered content layout
                    children: [
                      _buildWebHeroSection(context, isDark),
                      const SizedBox(height: 48),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _SectionHeader(title: "Your stats", subtitle: "Quick overview", isDark: isDark),
                      ),
                      const SizedBox(height: 12),
                      _StatsRow(stats: _stats, isDark: isDark),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => Navigator.pushNamed(context, '/analysis'),
                          icon: const Icon(Icons.analytics_outlined, color: Color(0xFF4CC9F0)),
                          label: const Text(
                            "View Full Analysis",
                            style: TextStyle(color: Color(0xFF4CC9F0), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _SectionHeader(title: "Continue", subtitle: "Jump back in", isDark: isDark),
                      ),
                      const SizedBox(height: 12),
                      _ContinueRow(
                        items: [_continueAI, _continueScan, _continueMarket],
                        onTap: (item) => Navigator.pushNamed(context, item["route"] as String),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 48),
                      Align(
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Text(
                              "Choose Your Workflow.",
                              style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Explore R2V tools built for every creative pipeline.",
                              style: TextStyle(color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      MouseRegion(
                        onEnter: (_) => setState(() => _pauseUseCaseAutoScroll = true),
                        onExit: (_) => setState(() => _pauseUseCaseAutoScroll = false),
                        child: UseCasesGrid(
                          items: _useCases,
                          selectedIndex: _selectedUseCase,
                          onTap: _onUseCaseTap,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(height: 32),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) {
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
                            child: FadeTransition(opacity: anim, child: child),
                          );
                        },
                        child: UseCaseDetailsSection(
                          key: ValueKey(_useCaseDetails[_selectedUseCase]["id"]),
                          data: _useCaseDetails[_selectedUseCase],
                          onCta: () => Navigator.pushNamed(
                            context,
                            _useCaseDetails[_selectedUseCase]["ctaRoute"],
                          ),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(height: 26),
                      if (_loadingSummary)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            "Updating…",
                            style: TextStyle(
                              color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebTopBar(BuildContext context, bool isDark) {
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
            boxShadow: isDark
                ? []
                : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 26, color: Color(0xFFBC70FF)),
              const SizedBox(width: 8),
              Text(
                "R2V",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              SizedBox(
                  width: 560,
                  child: R2VTopNavTabs(activeIndex: 0, isDark: isDark)),
              const SizedBox(width: 16),
              R2VNotificationBell(isDark: isDark),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/profile'),
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

  Widget _buildWebHeroSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          ),
          child: Text(
            "Welcome back, @$_displayName",
            style: TextStyle(color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 24),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: isDark 
                ? [Colors.white, const Color(0xFFBC70FF), const Color(0xFF4895EF)] 
                : [const Color(0xFF1E293B), const Color(0xFF8A4FFF), const Color(0xFF4895EF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            "Generate 3D Models",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white, // Required for ShaderMask
              fontSize: 56,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Turn text or images directly into high-precision 3D assets with accurate structure.",
          textAlign: TextAlign.center,
          style: TextStyle(color: isDark ? Colors.white.withOpacity(0.7) : Colors.black87, fontSize: 18, height: 1.5),
        ),
        const SizedBox(height: 36),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/aichat'),
              icon: const Icon(Icons.bolt_rounded, size: 24),
              label: const Text("Start AI Studio", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A4FFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: isDark ? 0 : 8,
                shadowColor: const Color(0xFF8A4FFF).withOpacity(0.5),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/photo_scan'),
              icon: const Icon(Icons.photo_camera_rounded, size: 24),
              label: const Text("Scan Object", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.white,
                foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                side: BorderSide(color: isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.1)),
                elevation: isDark ? 0 : 4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 56),
        // Two separate cards: the model viewer and the pipeline showcase.
        SizedBox(
          height: 480,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card 1: textured vs untextured comparison slider.
              Expanded(
                child: _GlassCard(
                  isDark: isDark,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.compare_arrows_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "Drag to compare texture",
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: _ModelComparisonSlider(
                              texturedSrc: "assets/Slider/model_slider.glb",
                              untexturedSrc: "assets/Slider/model_untextuerd_slider.glb",
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 22),
              // Card 2: pipeline showcase as a tall column.
              SizedBox(
                width: 300,
                child: _GlassCard(
                  isDark: isDark,
                  padding: const EdgeInsets.all(20),
                  child: _PipelineShowcase(isDark: isDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileHome(BuildContext context, bool isDark) {
    final double w = MediaQuery.of(context).size.width;
    final double contentWidth = w > 520 ? 520.0 : w;
    // This Scaffold uses extendBody: true, so content scrolls BEHIND the
    // floating LumaBar. Reserve the bar's footprint + safe area + breathing
    // room so the last items are never hidden behind the nav.
    final double navClearance =
        R2VSectionNav.barFootprint + MediaQuery.of(context).padding.bottom + 28;

    // No inner Scaffold / appBar. This mirrors Settings' single-Stack mobile
    // layout EXACTLY (SafeArea > Column > content) so there is no nested
    // Scaffold/Material that can paint a strip behind the floating nav. The
    // top pill is rendered inline instead of as an appBar; the LumaBar lives in
    // the OUTER build Stack (sibling of the background).
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildMobileTopPill(context, isDark),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 6, 16, navClearance),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectedTab == 0) _buildHomeTabMobile(context, isDark),
                      if (_selectedTab == 1) _buildAiTabMobile(context, isDark),
                      if (_selectedTab == 2) _buildScanTabMobile(context, isDark),
                      if (_selectedTab == 3) _buildMarketTabMobile(context, isDark),
                      if (_selectedTab == 5) _buildProfileTabMobile(context, isDark),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTopPill(BuildContext context, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: _collapsed ? 9 : 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.white),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFFBC70FF), size: 18),
          const SizedBox(width: 8),
          Text(
            "R2V",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: _collapsed ? 15 : 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          if (_loadingSummary) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? Colors.white.withOpacity(0.8) : const Color(0xFFBC70FF),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHomeTabMobile(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMobileHeroStack(context, isDark),
        const SizedBox(height: 32),
        _SectionHeader(title: "Your stats", subtitle: "Quick overview", isDark: isDark),
        const SizedBox(height: 12),
        _StatsRow(stats: _stats, isDark: isDark),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/analysis'),
            icon: const Icon(Icons.analytics_outlined, color: Color(0xFF4CC9F0)),
            label: const Text(
              "View Full Analysis",
              style: TextStyle(color: Color(0xFF4CC9F0), fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(title: "Continue", subtitle: "Jump back in", isDark: isDark),
        const SizedBox(height: 12),
        _ContinueRow(
          items: [_continueAI, _continueScan, _continueMarket],
          onTap: (item) => Navigator.pushNamed(context, item["route"] as String),
          forceVerticalOnMobile: true,
          isDark: isDark,
        ),
        const SizedBox(height: 32),
        Center(
          child: Column(
            children: [
              Text("Create For Free", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text("Explore powerful tools.", style: TextStyle(color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        UseCasesGrid(
          items: _useCases,
          selectedIndex: _selectedUseCase,
          onTap: _onUseCaseTap,
          isDark: isDark,
        ),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            );
          },
          child: UseCaseDetailsSectionMobile(
            key: ValueKey(_useCaseDetails[_selectedUseCase]["id"]),
            data: _useCaseDetails[_selectedUseCase],
            onCta: () => Navigator.pushNamed(context, _useCaseDetails[_selectedUseCase]["ctaRoute"]),
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileHeroStack(BuildContext context, bool isDark) {
    final double w = MediaQuery.of(context).size.width;
    // Comparison slider height scales with screen width but stays within a
    // premium, non-overflowing band (280–340) per the design spec.
    final double sliderH = (w * 0.78).clamp(280.0, 340.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.1)),
          ),
          child: Text(
            "Welcome back, @$_displayName",
            style: TextStyle(color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 18),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: isDark 
                ? [Colors.white, const Color(0xFFBC70FF)] 
                : [const Color(0xFF1E293B), const Color(0xFF8A4FFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            "Generate Production-Ready 3D Models",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Turn text or images directly into high-precision 3D assets.",
          textAlign: TextAlign.center,
          style: TextStyle(color: isDark ? Colors.white.withOpacity(0.75) : Colors.black87, fontSize: 14.5, height: 1.4),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/aichat'),
                icon: const Icon(Icons.bolt_rounded, size: 20),
                label: const Text("AI Studio", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A4FFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: isDark ? 0 : 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/photo_scan'),
                icon: const Icon(Icons.photo_camera_rounded, size: 20),
                label: const Text("Scan", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.white,
                  foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  side: BorderSide(color: isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.1)),
                  elevation: isDark ? 0 : 2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.15) : Colors.white),
                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Match desktop: the rotating model-prompt quote that used to
                  // render above the slider has been removed, so mobile now shows
                  // only the "Drag to compare texture" label here, exactly like
                  // the web/desktop slider card.
                  // Drag-to-compare texture slider — reuses the exact desktop
                  // widget, assets and synchronized-rotation logic, sized down
                  // for mobile. Only one instance mounts at a time (web vs
                  // mobile branch, Home tab only), so the shared "r2v-slider-"
                  // DOM ids never collide.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.compare_arrows_rounded,
                          color: isDark ? Colors.white70 : Colors.black54, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        "Drag to compare texture",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: sliderH,
                    width: double.infinity,
                    child: _ModelComparisonSlider(
                      texturedSrc: "assets/Slider/model_slider.glb",
                      untexturedSrc: "assets/Slider/model_untextuerd_slider.glb",
                      isDark: isDark,
                    ),
                  ),
                  // PERFORMANCE (mobile): the AI Pipeline showcase — an input
                  // image plus TWO heavy GLB model_viewer_plus instances
                  // (Generated Mesh + Generated Texture) — is intentionally NOT
                  // built on mobile. It is removed from the widget tree here
                  // (not hidden with Opacity/Visibility), so the model viewers
                  // never mount. Desktop keeps it (see _buildWebHeroSection).
                  // The texture comparison slider above is the only model
                  // content rendered on mobile.
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiTabMobile(BuildContext context, bool isDark) {
    return _HomeActionCard(
      title: "AI Studio",
      subtitle: "Text → 3D concepts & variations",
      icon: Icons.bolt_rounded,
      accent: const Color(0xFF8A4FFF),
      onTap: () => Navigator.pushNamed(context, '/aichat'),
      primaryLabel: "Open AI Studio",
      secondaryLabel: "Templates",
      onSecondaryTap: () => _toast(context, "Templates coming soon"),
      bullets: const ["Prompt", "Variants", "Export"],
      isDark: isDark,
    );
  }

  Widget _buildScanTabMobile(BuildContext context, bool isDark) {
    return _HomeActionCard(
      title: "Scan",
      subtitle: "Photo → 3D model (photogrammetry)",
      icon: Icons.photo_camera_rounded,
      accent: const Color(0xFFF72585),
      onTap: () => Navigator.pushNamed(context, '/photo_scan'),
      primaryLabel: "Start Scan",
      secondaryLabel: "Tips",
      onSecondaryTap: () => _openTips(context, isDark),
      bullets: const ["Capture", "Rebuild", "STL/GLB"],
      isDark: isDark,
    );
  }

  Widget _buildMarketTabMobile(BuildContext context, bool isDark) {
    return _HomeActionCard(
      title: "Marketplace",
      subtitle: "Browse assets & packs",
      icon: Icons.storefront_rounded,
      accent: const Color(0xFF4895EF),
      onTap: () => Navigator.pushNamed(context, '/explore'),
      primaryLabel: "Open Marketplace",
      secondaryLabel: "Saved",
      onSecondaryTap: () => setState(() => _activeMarketModel = _models.first),
      bullets: const ["Preview", "Free/Paid", "Creators"],
      isDark: isDark,
    );
  }

  Widget _buildProfileTabMobile(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: "Profile", subtitle: "Account shortcuts", isDark: isDark),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _GlassSmallAction(
                icon: Icons.person_rounded,
                title: "View Profile",
                subtitle: "Your info & activity",
                onTap: () => Navigator.pushNamed(context, '/profile'),
                accent: const Color(0xFFBC70FF),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GlassSmallAction(
                icon: Icons.settings_rounded,
                title: "Settings",
                subtitle: "Preferences",
                onTap: () => Navigator.pushNamed(context, '/settings'),
                accent: const Color(0xFF4895EF),
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionHeader(title: "Tip", subtitle: "Quick scan tips", isDark: isDark),
        const SizedBox(height: 10),
        _GlassSmallAction(
          icon: Icons.lightbulb_rounded,
          title: "Open Scan Tips",
          subtitle: "Lighting, angles, consistency",
          onTap: () => _openTips(context, isDark),
          accent: const Color(0xFFF72585),
          isDark: isDark,
        ),
      ],
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _openTips(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(12),
        child: _TipsSheet(isDark: isDark),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDark;

  const _SectionHeader({required this.title, required this.subtitle, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54, fontSize: 13)),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Map<String, int> stats;
  final bool isDark;

  const _StatsRow({required this.stats, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final isWeb = c.maxWidth >= 900;
      final items = stats.entries.toList();

      return Row(
        children: items.map((e) {
          final idx = items.indexOf(e);
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: idx == items.length - 1 ? 0 : (isWeb ? 14 : 10)),
              child: _MiniStatCard(label: e.key, value: e.value, isDark: isDark),
            ),
          );
        }).toList(),
      );
    });
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final int value;
  final bool isDark;

  const _MiniStatCard({required this.label, required this.value, required this.isDark});

  Color _accentFor(String label) {
    switch (label.toLowerCase()) {
      case "models":
        return const Color(0xFF8A4FFF);
      case "scans":
        return const Color(0xFFF72585);
      case "downloads":
        return const Color(0xFF4895EF);
      default:
        return const Color(0xFFBC70FF);
    }
  }

  IconData _iconFor(String label) {
    switch (label.toLowerCase()) {
      case "models":
        return Icons.view_in_ar_rounded;
      case "scans":
        return Icons.photo_camera_rounded;
      case "downloads":
        return Icons.download_rounded;
      default:
        return Icons.insights_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(label);
    final icon = _iconFor(label);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withOpacity(0.55)),
                ),
                child: Icon(icon, color: isDark ? Colors.white.withOpacity(0.95) : accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isDark ? Colors.white.withOpacity(0.70) : Colors.black54, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$value",
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueRow extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item) onTap;
  final bool forceVerticalOnMobile;
  final bool isDark;

  const _ContinueRow({
    required this.items,
    required this.onTap,
    this.forceVerticalOnMobile = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 520;

    if (forceVerticalOnMobile && isNarrow) {
      return Column(
        children: items
            .map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ContinueCard(item: it, onTap: () => onTap(it), isDark: isDark),
                ))
            .toList(),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final isWeb = c.maxWidth >= 900;

      if (isWeb) {
        return Row(
          children: items.map((it) {
            final idx = items.indexOf(it);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: idx == items.length - 1 ? 0 : 14),
                child: _ContinueCard(item: it, onTap: () => onTap(it), isDark: isDark),
              ),
            );
          }).toList(),
        );
      }

      return SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            return SizedBox(
              width: 290,
              child: _ContinueCard(item: items[i], onTap: () => onTap(items[i]), isDark: isDark),
            );
          },
        ),
      );
    });
  }
}

class _ContinueCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool isDark;

  const _ContinueCard({required this.item, required this.onTap, required this.isDark});

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final Color accent = widget.item["accent"] as Color;
    final IconData icon = widget.item["icon"] as IconData;
    final String title = widget.item["title"] as String;
    final String subtitle = widget.item["subtitle"] as String;
    final isDark = widget.isDark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.identity()..translate(0.0, (_hover && isWeb) ? -5.0 : 0.0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hover
                      ? (isDark ? Colors.white.withOpacity(0.20) : Colors.black.withOpacity(0.1))
                      : (isDark ? Colors.white.withOpacity(0.12) : Colors.white),
                ),
                boxShadow: [
                  if (isDark)
                    BoxShadow(
                      blurRadius: _hover ? 24 : 18,
                      color: Colors.black.withOpacity(_hover ? 0.45 : 0.30),
                      offset: const Offset(0, 12),
                    )
                  else
                    BoxShadow(
                      blurRadius: _hover ? 16 : 8,
                      color: Colors.black.withOpacity(0.04),
                      offset: const Offset(0, 4),
                    )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.withOpacity(0.55)),
                    ),
                    child: Icon(icon, color: isDark ? Colors.white : accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.white.withOpacity(0.70) : Colors.black54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: isDark ? Colors.white70 : Colors.black38),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Professional single-row segmented tab bar for use cases.
class UseCasesGrid extends StatelessWidget {
  final List<Map<String, String>> items;
  final int selectedIndex;
  final void Function(int index) onTap;
  final bool isDark;

  const UseCasesGrid({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 900;

        if (isWide) {
          // All tabs share a single row, evenly distributed.
          return Row(
            children: List.generate(items.length, (i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 10),
                  child: _UseCaseTab(
                    title: items[i]["title"] ?? "",
                    id: items[i]["id"],
                    isActive: i == selectedIndex,
                    onTap: () => onTap(i),
                    isDark: isDark,
                  ),
                ),
              );
            }),
          );
        }

        // Mobile: one horizontally scrollable row.
        return SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => SizedBox(
              width: 100,
              child: _UseCaseTab(
                title: items[i]["title"] ?? "",
                id: items[i]["id"],
                isActive: i == selectedIndex,
                onTap: () => onTap(i),
                isDark: isDark,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UseCaseTab extends StatefulWidget {
  final String title;
  final String? id;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const _UseCaseTab({
    required this.title,
    required this.id,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_UseCaseTab> createState() => _UseCaseTabState();
}

class _UseCaseTabState extends State<_UseCaseTab> {
  bool _hover = false;

  IconData _iconFor(String? id) {
    switch (id) {
      case 'film':
        return Icons.movie_creation_rounded;
      case 'product':
        return Icons.design_services_rounded;
      case 'edu':
        return Icons.school_rounded;
      case 'game':
        return Icons.sports_esports_rounded;
      case 'print':
        return Icons.print_rounded;
      case 'vr':
        return Icons.view_in_ar_rounded;
      case 'interior':
        return Icons.weekend_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _accentFor(String? id) {
    switch (id) {
      case 'film':
        return const Color(0xFF9CA3AF);
      case 'product':
        return const Color(0xFF38BDF8);
      case 'edu':
        return const Color(0xFFFDE68A);
      case 'game':
        return const Color(0xFF22D3EE);
      case 'print':
        return const Color(0xFFA3E635);
      case 'vr':
        return const Color(0xFFC084FC);
      case 'interior':
        return const Color(0xFFFCA5A5);
      default:
        return const Color(0xFFBC70FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = _accentFor(widget.id);
    final active = widget.isActive;
    final highlight = active || _hover;
    final title = widget.title.replaceAll('\n', ' ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          transform: Matrix4.identity()..translate(0.0, highlight ? -3.0 : 0.0),
          decoration: BoxDecoration(
            color: active
                ? accent.withOpacity(isDark ? 0.20 : 0.14)
                : (isDark
                    ? Colors.white.withOpacity(highlight ? 0.10 : 0.05)
                    : Colors.white.withOpacity(highlight ? 0.92 : 0.65)),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active
                  ? accent.withOpacity(isDark ? 0.70 : 0.55)
                  : (isDark ? Colors.white.withOpacity(0.10) : Colors.white),
              width: active ? 1.4 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: accent.withOpacity(isDark ? 0.30 : 0.20),
                      blurRadius: 18,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    )
                  ]
                : (isDark
                    ? const []
                    : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(active ? 0.28 : 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withOpacity(active ? 0.70 : 0.40)),
                ),
                child: Icon(_iconFor(widget.id), size: 19, color: isDark ? Colors.white : accent),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active
                        ? (isDark ? Colors.white : const Color(0xFF1E293B))
                        : (isDark ? Colors.white.withOpacity(0.75) : Colors.black54),
                    fontSize: 11.5,
                    height: 1.12,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UseCaseDetailsSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onCta;
  final bool isDark;

  const UseCaseDetailsSection({
    super.key,
    required this.data,
    required this.onCta,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = (data["accent"] as Color?) ?? const Color(0xFFBC70FF);
    final bullets = (data["bullets"] as List?)?.cast<String>() ?? const <String>[];
    final String title = data["title"] ?? "";

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [accent.withOpacity(0.14), Colors.white.withOpacity(0.04)]
                  : [accent.withOpacity(0.10), Colors.white.withOpacity(0.78)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: isDark ? accent.withOpacity(0.22) : Colors.white),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(isDark ? 0.20 : 0.14),
                blurRadius: 44,
                spreadRadius: -10,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(isDark ? 0.18 : 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accent.withOpacity(0.50)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: isDark ? Colors.white : accent),
                          const SizedBox(width: 7),
                          Text(
                            "WORKFLOW",
                            style: TextStyle(
                              color: isDark ? Colors.white.withOpacity(0.92) : accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [Colors.white, accent]
                            : [const Color(0xFF1E293B), accent],
                      ).createShader(bounds),
                      child: Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontSize: 44, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -0.8),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      data["subtitle"] ?? "",
                      style: TextStyle(color: isDark ? Colors.white.withOpacity(0.78) : Colors.black87, fontSize: 15, height: 1.45),
                    ),
                    const SizedBox(height: 24),
                    for (final b in bullets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.20),
                                shape: BoxShape.circle,
                                border: Border.all(color: accent.withOpacity(0.60), width: 1),
                                boxShadow: [
                                  BoxShadow(color: accent.withOpacity(isDark ? 0.30 : 0.18), blurRadius: 10, spreadRadius: -2),
                                ],
                              ),
                              child: Icon(Icons.check_rounded, size: 15, color: isDark ? Colors.white : accent),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                b,
                                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: onCta,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(data["cta"] ?? "Explore More"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? accent.withOpacity(0.18) : accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        side: isDark ? BorderSide(color: accent.withOpacity(0.55), width: 1) : BorderSide.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    height: 360,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                      border: Border.all(color: accent.withOpacity(isDark ? 0.22 : 0.14)),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            data["preview"] ?? "",
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Center(child: Icon(Icons.image_outlined, color: isDark ? Colors.white.withOpacity(0.5) : Colors.black26, size: 48)),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  accent.withOpacity(isDark ? 0.45 : 0.30),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.28),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                                    const SizedBox(width: 8),
                                    Text(
                                      title,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UseCaseDetailsSectionMobile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onCta;
  final bool isDark;

  const UseCaseDetailsSectionMobile({
    super.key,
    required this.data,
    required this.onCta,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = (data["accent"] as Color?) ?? const Color(0xFFBC70FF);
    final bullets = (data["bullets"] as List?)?.cast<String>() ?? const <String>[];
    final String title = data["title"] ?? "";

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [accent.withOpacity(0.14), Colors.white.withOpacity(0.04)]
                  : [accent.withOpacity(0.10), Colors.white.withOpacity(0.78)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? accent.withOpacity(0.22) : Colors.white),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(isDark ? 0.18 : 0.12),
                blurRadius: 30,
                spreadRadius: -8,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(isDark ? 0.18 : 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withOpacity(0.50)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 12, color: isDark ? Colors.white : accent),
                    const SizedBox(width: 6),
                    Text(
                      "WORKFLOW",
                      style: TextStyle(
                        color: isDark ? Colors.white.withOpacity(0.92) : accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark ? [Colors.white, accent] : [const Color(0xFF1E293B), accent],
                ).createShader(bounds),
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 26, height: 1.1, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                data["subtitle"] ?? "",
                style: TextStyle(color: isDark ? Colors.white.withOpacity(0.78) : Colors.black87, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              for (final b in bullets.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: accent.withOpacity(0.55), width: 1),
                        ),
                        child: Icon(Icons.check_rounded, size: 13, color: isDark ? Colors.white : accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b,
                          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          data["preview"] ?? "",
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Center(child: Icon(Icons.image_outlined, color: isDark ? Colors.white.withOpacity(0.5) : Colors.black26, size: 42)),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [accent.withOpacity(isDark ? 0.42 : 0.28), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(data["cta"] ?? "Explore More"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? accent.withOpacity(0.18) : accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: isDark ? BorderSide(color: accent.withOpacity(0.55), width: 1) : BorderSide.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Showcase of the R2V pipeline: input image -> generated mesh -> generated texture.
class _PipelineShowcase extends StatefulWidget {
  final bool isDark;
  final bool horizontal;

  const _PipelineShowcase({required this.isDark, this.horizontal = false});

  @override
  State<_PipelineShowcase> createState() => _PipelineShowcaseState();
}

class _PipelineShowcaseState extends State<_PipelineShowcase> {
  static const String _inputImg = "assets/World_Cup.png";
  static const String _meshModel = "assets/World_Cup_untextured.glb";
  static const String _texModel = "assets/World_Cup.glb";
  static const Color _inputAccent = Color(0xFF4895EF);
  static const Color _meshAccent = Color(0xFF8A4FFF);
  static const Color _texAccent = Color(0xFFF72585);

  int _active = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted) return;
      setState(() => _active = (_active + 1) % 3);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    final stages = [
      _stage(
        label: "Input Image",
        icon: Icons.image_rounded,
        accent: _inputAccent,
        active: _active == 0,
        visual: _imageVisual(_inputImg),
      ),
      _stage(
        label: "Generated Mesh",
        icon: Icons.grid_on_rounded,
        accent: _meshAccent,
        active: _active == 1,
        visual: _modelVisual(_meshModel, exposure: 0.45),
      ),
      _stage(
        label: "Generated Texture",
        icon: Icons.palette_rounded,
        accent: _texAccent,
        active: _active == 2,
        visual: _modelVisual(_texModel),
      ),
    ];

    if (widget.horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: stages[0]),
          _connector(active: _active == 0, accent: _meshAccent, horizontal: true),
          Expanded(child: stages[1]),
          _connector(active: _active == 1, accent: _texAccent, horizontal: true),
          Expanded(child: stages[2]),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 14, color: _meshAccent),
            const SizedBox(width: 6),
            Text(
              "AI Pipeline",
              style: TextStyle(
                color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF1E293B),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: stages[0]),
        _connector(active: _active == 0, accent: _meshAccent),
        Expanded(child: stages[1]),
        _connector(active: _active == 1, accent: _texAccent),
        Expanded(child: stages[2]),
      ],
    );
  }

  // Same radial backdrop as the large hero model viewer, so every stage matches.
  BoxDecoration get _heroBg => BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0xFF8A4FFF).withOpacity(0.15),
            const Color(0xFF4895EF).withOpacity(0.05),
            Colors.transparent,
          ],
        ),
      );

  Widget _modelVisual(String src, {double exposure = 1.0}) {
    return Container(
      decoration: _heroBg,
      child: _StableModelViewer(
        key: ValueKey('stable-$src'),
        isDark: widget.isDark,
        viewer: ModelViewer(
          key: ValueKey(src),
          src: _mvUrl(src),
          backgroundColor: Colors.transparent,
          autoRotate: true,
          autoRotateDelay: 0,
          rotationPerSecond: "30deg",
          cameraControls: false,
          disableZoom: true,
          environmentImage: "neutral",
          exposure: exposure,
        ),
      ),
    );
  }

  Widget _imageVisual(String src) {
    return Container(
      decoration: _heroBg,
      padding: const EdgeInsets.all(8),
      child: Image.asset(src, fit: BoxFit.contain, errorBuilder: _imgError),
    );
  }

  Widget _imgError(BuildContext context, Object error, StackTrace? stack) {
    return Container(
      color: widget.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
      child: Icon(Icons.image_outlined, color: widget.isDark ? Colors.white30 : Colors.black26, size: 28),
    );
  }

  Widget _connector({required bool active, required Color accent, bool horizontal = false}) {
    final dim = widget.isDark ? Colors.white24 : Colors.black26;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: horizontal ? 0 : 5, horizontal: horizontal ? 5 : 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Icon(
          horizontal ? Icons.arrow_forward_rounded : Icons.arrow_downward_rounded,
          key: ValueKey(active),
          size: 16,
          color: active ? accent : dim,
        ),
      ),
    );
  }

  Widget _stage({
    required String label,
    required IconData icon,
    required Color accent,
    required bool active,
    required Widget visual,
  }) {
    final isDark = widget.isDark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? accent.withOpacity(0.9) : (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08)),
          width: active ? 1.6 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: accent.withOpacity(0.45), blurRadius: 18, spreadRadius: -3, offset: const Offset(0, 6))]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            visual,
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  Icon(icon, size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: accent.withOpacity(0.8), blurRadius: 8, spreadRadius: 1)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Before/after wipe slider comparing a textured and untextured GLB at a fixed,
// locked camera angle. Both viewers render full-size; the textured one is
// clipped to the left of the divider so the reveal lines up perfectly.
class _ModelComparisonSlider extends StatefulWidget {
  final String texturedSrc;
  final String untexturedSrc;
  final bool isDark;

  const _ModelComparisonSlider({
    required this.texturedSrc,
    required this.untexturedSrc,
    required this.isDark,
  });

  @override
  State<_ModelComparisonSlider> createState() => _ModelComparisonSliderState();
}

class _ModelComparisonSliderState extends State<_ModelComparisonSlider> {
  // Both layers rotate together as one synchronized turntable. Native
  // auto-rotate is OFF on both <model-viewer> instances (two independent
  // auto-rotate clocks drift apart because the textured GLB is ~4x larger and
  // reveals later). Instead, a single rAF loop in web/index.html drives the
  // same `camera-orbit` onto both elements (matched by id prefix
  // "r2v-slider-") from one shared clock, so they can never drift. These
  // constants are the fixed parts of that shared orbit and must match the JS.
  static const String _domIdTextured = "r2v-slider-textured";
  static const String _domIdUntextured = "r2v-slider-untextured";
  static const String _initialOrbit = "0deg 75deg 105%"; // before first JS tick
  static const String _cameraTarget = "auto auto auto";  // identical bbox center
  static const String _fieldOfView = "auto";             // identical framing
  double _pos = 0.5;

  BoxDecoration get _bg => BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0xFF8A4FFF).withOpacity(0.15),
            const Color(0xFF4895EF).withOpacity(0.05),
            Colors.transparent,
          ],
        ),
        border: Border.all(
          color: widget.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        ),
      );

  // Both layers are built identically except for `src` and `domId`. Rotation is
  // driven externally (see web/index.html) so neither viewer auto-rotates on its
  // own — they are kept in perfect lock-step from one shared clock.
  Widget _viewer(String src, String domId, {double exposure = 0.45}) {
    return _StableModelViewer(
      key: ValueKey('stable-$src'),
      isDark: widget.isDark,
      viewer: ModelViewer(
        key: ValueKey(src),
        id: domId,
        src: _mvUrl(src),
        backgroundColor: Colors.transparent,
        autoRotate: false,
        cameraControls: false,
        disableZoom: true,
        cameraOrbit: _initialOrbit,
        cameraTarget: _cameraTarget,
        fieldOfView: _fieldOfView,
        interactionPrompt: InteractionPrompt.none,
        environmentImage: "neutral",
        exposure: exposure,
      ),
    );
  }

  Widget _label(String text, Color accent, {required bool left}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void update(double dx) => setState(() => _pos = (dx / w).clamp(0.0, 1.0));

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => update(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
            child: Stack(
              children: [
                Positioned.fill(child: DecoratedBox(decoration: _bg)),
                // Untextured fills the whole frame (base layer).
                Positioned.fill(child: _viewer(widget.untexturedSrc, _domIdUntextured)),
                // Textured layer, laid out full-size; only its PAINT is clipped
                // to the left of the divider so it overlaps the base exactly.
                Positioned.fill(
                  child: ClipRect(
                    clipper: _RevealClipper(_pos),
                    child: _viewer(widget.texturedSrc, _domIdTextured),
                  ),
                ),
                Positioned(left: 10, bottom: 10, child: _label("Textured", const Color(0xFFF72585), left: true)),
                Positioned(right: 10, bottom: 10, child: _label("Untextured", const Color(0xFF8A4FFF), left: false)),
                // Divider line.
                Positioned(
                  left: _pos * w - 1,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(width: 2, color: Colors.white.withOpacity(0.9)),
                  ),
                ),
                // Drag handle, near the top of the divider.
                Positioned(
                  left: _pos * w - 18,
                  top: 8,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, size: 20, color: Color(0xFF1E293B)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  final double fraction;

  _RevealClipper(this.fraction);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(covariant _RevealClipper oldClipper) => oldClipper.fraction != fraction;
}

/// Wraps a [ModelViewer] so the broken/shifted first frame that
/// model_viewer_plus can show on a cold web load is never seen.
///
/// On web each `<model-viewer>` lives in a Flutter `HtmlElementView` platform
/// view and frames its camera once — against whatever size the element happens
/// to have when the GLB and the model-viewer JS module become ready. On a first
/// load those race, so framing can lock against a transient size (the
/// shifted/partial look that a refresh "fixes" because caches+layout are warm).
///
/// This widget removes the race instead of hiding it:
///   1. It paints a premium placeholder at full size first, so the box is laid
///      out and stable before any `<model-viewer>` exists.
///   2. It mounts the real viewer into that already-stable box on the next
///      frame, so framing is computed against the final size.
///   3. It keeps the placeholder over the viewer for a short settle window,
///      then fades it out to reveal the stabilized model.
///
/// No camera orbit/target is forced and the wrapped viewer's parameters are
/// passed through untouched, so capture/camera behaviour is preserved.
class _StableModelViewer extends StatefulWidget {
  /// The fully-configured [ModelViewer] to reveal once it is stable.
  final Widget viewer;
  final bool isDark;
  final BorderRadius borderRadius;

  /// How long to keep the placeholder up after the viewer mounts, giving the
  /// underlying `<model-viewer>` time to load the GLB and frame against the
  /// now-stable size before it is revealed.
  final Duration settle;

  const _StableModelViewer({
    required this.viewer,
    required this.isDark,
    this.borderRadius = BorderRadius.zero,
    this.settle = const Duration(milliseconds: 700),
    super.key,
  });

  @override
  State<_StableModelViewer> createState() => _StableModelViewerState();
}

class _StableModelViewerState extends State<_StableModelViewer> {
  bool _mounted = false; // viewer added to the (stable) box
  bool _revealed = false; // placeholder faded out

  @override
  void initState() {
    super.initState();
    // First frame: the placeholder has now established a stable, full-size box.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Mount the viewer into that stable box so it frames correctly.
      setState(() => _mounted = true);
      // Let the GLB load + frame against the stable size, then reveal.
      Future.delayed(widget.settle, () {
        if (mounted) setState(() => _revealed = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Always full-size so framing is computed against the final dimensions.
        if (_mounted) widget.viewer,
        // Premium loading state; fades out only once the model is stable.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _revealed,
            child: AnimatedOpacity(
              opacity: _revealed ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              child: _ModelLoadingPlaceholder(
                isDark: widget.isDark,
                borderRadius: widget.borderRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A subtle, on-brand loading state shown while a [_StableModelViewer] settles.
class _ModelLoadingPlaceholder extends StatefulWidget {
  final bool isDark;
  final BorderRadius borderRadius;

  const _ModelLoadingPlaceholder({
    required this.isDark,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  State<_ModelLoadingPlaceholder> createState() => _ModelLoadingPlaceholderState();
}

class _ModelLoadingPlaceholderState extends State<_ModelLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8A4FFF);
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: DecoratedBox(
        // Matches the hero/pipeline radial backdrop so the reveal is seamless.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [
              accent.withOpacity(0.16),
              const Color(0xFF4895EF).withOpacity(0.05),
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.45, end: 1.0)
                .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.06)
                  .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(widget.isDark ? 0.25 : 0.04),
                  border: Border.all(color: accent.withOpacity(0.55), width: 1.4),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.35), blurRadius: 22, spreadRadius: -4),
                  ],
                ),
                child: Icon(Icons.view_in_ar_rounded, color: accent.withOpacity(0.95), size: 26),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Reusable frosted-glass card matching the app's hero styling.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry padding;

  const _GlassCard({
    required this.child,
    required this.isDark,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.6),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.15) : Colors.white),
            boxShadow: isDark
                ? []
                : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback? onSecondaryTap;
  final List<String> bullets;
  final bool isDark;

  const _HomeActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onSecondaryTap,
    required this.bullets,
    required this.isDark,
  });

  @override
  State<_HomeActionCard> createState() => _HomeActionCardState();
}

class _HomeActionCardState extends State<_HomeActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final isDark = widget.isDark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.identity()..translate(0.0, (_hover && isWeb) ? -6.0 : 0.0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _hover
                      ? (isDark ? Colors.white.withOpacity(0.22) : Colors.black.withOpacity(0.1))
                      : (isDark ? Colors.white.withOpacity(0.12) : Colors.white),
                  width: _hover ? 1.3 : 1,
                ),
                boxShadow: [
                  if (isDark)
                    BoxShadow(
                      blurRadius: _hover ? 28 : 18,
                      color: Colors.black.withOpacity(_hover ? 0.45 : 0.30),
                      offset: const Offset(0, 12),
                    )
                  else
                    BoxShadow(
                      blurRadius: _hover ? 15 : 10,
                      color: Colors.black.withOpacity(0.05),
                      offset: const Offset(0, 5),
                    )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: widget.accent.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: widget.accent.withOpacity(0.55), width: 1),
                        ),
                        child: Icon(widget.icon, color: isDark ? Colors.white : widget.accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: isDark ? Colors.white.withOpacity(0.72) : Colors.black54, height: 1.25),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.bullets
                        .map((b) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.transparent),
                              ),
                              child: Text(
                                b,
                                style: TextStyle(
                                  color: isDark ? Colors.white.withOpacity(0.88) : Colors.black87,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: widget.onTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? widget.accent.withOpacity(0.22) : widget.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: isDark ? BorderSide(color: widget.accent.withOpacity(0.55), width: 1) : BorderSide.none,
                          ),
                          child: Text(widget.primaryLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onSecondaryTap,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                            side: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(widget.secondaryLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSmallAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;
  final bool isDark;

  const _GlassSmallAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
              boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withOpacity(0.55)),
                  ),
                  child: Icon(icon, color: isDark ? Colors.white : accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isDark ? Colors.white.withOpacity(0.70) : Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: isDark ? Colors.white70 : Colors.black38, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TipsSheet extends StatelessWidget {
  final bool isDark;
  const _TipsSheet({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.35) : Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Scan Tips", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              _tip("Use bright, even lighting (no harsh shadows).", isDark),
              _tip("Capture 20–40 photos from all angles.", isDark),
              _tip("Keep the object centered, move around it.", isDark),
              _tip("Avoid reflective/transparent objects if possible.", isDark),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFFF72585).withOpacity(0.22) : const Color(0xFFF72585),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: isDark ? BorderSide(color: const Color(0xFFF72585).withOpacity(0.55), width: 1) : BorderSide.none,
                  ),
                  child: const Text("Got it", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tip(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87, height: 1.25))),
        ],
      ),
    );
  }
}

class _HomeMarketModelPanel extends StatelessWidget {
  final MarketModel model;
  final VoidCallback onClose;
  final bool isDark;

  const _HomeMarketModelPanel({required this.model, required this.onClose, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWeb = size.width >= 900;

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withOpacity(0.60),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWeb ? 1100 : size.width - 18,
                maxHeight: isWeb ? 680 : size.height * 0.86,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black.withOpacity(0.22) : Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.white),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                            InkWell(
                              onTap: onClose,
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.05),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.transparent),
                                ),
                                child: Icon(Icons.close, size: 18, color: isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              color: isDark ? Colors.black.withOpacity(0.18) : Colors.black.withOpacity(0.05),
                              child: ModelViewer(
                                key: ValueKey(model.glbAssetPath),
                                src: _mvUrl(model.glbAssetPath),
                                poster: _mvUrl(model.posterAssetPath),
                                backgroundColor: Colors.transparent,
                                cameraControls: true,
                                autoRotate: true,
                                environmentImage: "neutral",
                              ),
                            ),
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
    );
  }
}

class _GlassBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GlassBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Render through the shared glassmorphic "LumaBar" using the ONE shared nav
    // config (R2VSectionNav.items) so Home's bar matches every other page.
    // Home keeps its own tap behavior (internal tab switch + route to Talent);
    // LumaBar only owns the visual + glow animation.
    return LumaBar(
      items: R2VSectionNav.items,
      currentIndex: currentIndex,
      onTap: onTap,
    );
  }
}

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
              top: -150,
              right: -50,
              child: Transform.rotate(
                angle: -0.35,
                child: Row(
                  children: [
                    _GradientBlob(isDark: isDark),
                    const SizedBox(width: 50),
                    _GradientBlob(isDark: isDark),
                    const SizedBox(width: 50),
                    _GradientBlob(isDark: isDark),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -50,
              right: -150,
              child: Transform.rotate(
                angle: -0.35,
                child: Row(
                  children: [
                    _GradientBlob(isDark: isDark),
                    const SizedBox(width: 50),
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
        width: 140,
        height: 400,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [Colors.white.withOpacity(0.15), Colors.blue.shade300.withOpacity(0.35)]
                : [const Color(0xFFBC70FF).withOpacity(0.25), const Color(0xFF4895EF).withOpacity(0.25)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
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
    int target = (area / 18000).round();
    target = target.clamp(35, 95);

    if (_ps.length == target) return;

    _ps = List.generate(target, (i) {
      final pos = Offset(_rng.nextDouble() * s.width, _rng.nextDouble() * s.height);
      final speed = 8 + _rng.nextDouble() * 18;
      final ang = _rng.nextDouble() * pi * 2;
      final vel = Offset(cos(ang), sin(ang)) * speed;
      final r = 1.2 + _rng.nextDouble() * 1.9;
      return _Particle(pos: pos, vel: vel, radius: r);
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
          painter: _MeshPainter(
            particles: _ps,
            time: _t,
            size: s,
            mouse: _mouse,
            hasMouse: _hasMouse,
            isDark: widget.isDark,
          ),
        ),
      );
    });
  }
}

class _Particle {
  Offset pos;
  Offset vel;
  final double radius;

  _Particle({required this.pos, required this.vel, required this.radius});
}

class _MeshPainter extends CustomPainter {
  final List<_Particle> particles;
  final double time;
  final Size size;
  final Offset mouse;
  final bool hasMouse;
  final bool isDark;

  _MeshPainter({
    required this.particles,
    required this.time,
    required this.size,
    required this.mouse,
    required this.hasMouse,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size _) {
    final rect = Offset.zero & size;

    final bgColors = isDark
        ? const [Color(0xFF0F1118), Color(0xFF141625), Color(0xFF0B0D14)]
        : const [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFE2E8F0)];

    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: bgColors,
        stops: const [0.0, 0.55, 1.0],
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

    glowBlob(center + wobble, 280, isDark ? const Color(0xFF8A4FFF) : const Color(0xFFA855F7), isDark ? 0.18 : 0.12);
    glowBlob(
      Offset(size.width * 0.25, size.height * 0.70) + Offset(cos(time * 0.35) * 35, sin(time * 0.32) * 28),
      240,
      isDark ? const Color(0xFF4895EF) : const Color(0xFF38BDF8),
      isDark ? 0.14 : 0.10,
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
          linePaint.color = isDark
              ? Colors.white.withOpacity(0.06 * t)
              : const Color(0xFF8A4FFF).withOpacity(0.15 * t);
          canvas.drawLine(ap, bp, linePaint);
        }
      }
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final pos = p.pos + parallax * 0.6;
      dotPaint.color = isDark ? Colors.white.withOpacity(0.12) : const Color(0xFF8A4FFF).withOpacity(0.25);
      canvas.drawCircle(pos, p.radius, dotPaint);
    }

    final vignetteColors = isDark
        ? [Colors.transparent, Colors.black.withOpacity(0.55)]
        : [Colors.transparent, Colors.white.withOpacity(0.4)];

    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.15,
        colors: vignetteColors,
        stops: const [0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) => true;
}