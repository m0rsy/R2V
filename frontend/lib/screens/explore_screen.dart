import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../api/r2v_api.dart';
import 'widgets/r2v_top_nav_tabs.dart'; // shared desktop top-nav tab strip
import 'widgets/r2v_notification_bell.dart';
import 'widgets/share_to_follower_sheet.dart';
import '../api/api_exception.dart';
import '../api/marketplace_service.dart';
import '../utils/web_model_viewer_capture.dart';
import '../widgets/ui/premium_input.dart';
import '../widgets/premium_thumbnail.dart';
import 'widgets/report_dialog.dart';
import 'widgets/r2v_section_nav.dart';

// ============================================================
// ✅ Explore Screen (WEB: Centered 3-col grid + RIGHT details panel)
// ============================================================

class ExploreScreen extends StatefulWidget {
  /// Optional asset id from a deep link (e.g. `/explore?asset=<id>`). When set,
  /// the matching asset's detail panel opens automatically once assets load.
  final String? initialAssetId;

  const ExploreScreen({super.key, this.initialAssetId});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {

  String selectedCategory = "All";
  MarketplaceAsset? _selectedAsset;
  List<MarketplaceAsset> _assets = [];
  bool _loadingAssets = false;
  String? _assetsError;
  String _searchQuery = "";

  static const double _creatorCardMinWidth = 220;

  final List<String> _categories = const [
    "All",
    "Characters",
    "Objects",
    "Vehicles",
    "Environments",
    "Stylized",
    "Realistic",
  ];

  bool _initialAssetHandled = false;

  @override
  void initState() {
    super.initState();
    _loadAssets().then((_) => _maybeOpenInitialAsset());
  }

  /// Opens the asset detail panel for a deep-linked asset id (once). Resolves
  /// the asset from the loaded grid, falling back to a direct fetch so links to
  /// assets outside the first page still open.
  Future<void> _maybeOpenInitialAsset() async {
    final id = widget.initialAssetId;
    if (id == null || id.isEmpty || _initialAssetHandled || !mounted) return;
    _initialAssetHandled = true;

    MarketplaceAsset? asset;
    for (final a in _assets) {
      if (a.id == id) {
        asset = a;
        break;
      }
    }
    if (asset == null) {
      try {
        asset = await r2vMarketplace.getAsset(id);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That asset is no longer available.')),
        );
        return;
      }
    }
    if (!mounted) return;
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isWeb) {
      setState(() => _selectedAsset = asset);
    } else {
      _openMobileDetails(asset, isDark);
    }
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loadingAssets = true;
      _assetsError = null;
    });
    try {
      final data = await r2vMarketplace.listAssets(limit: 60);
      if (!mounted) return;
      setState(() {
        _assets = data;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _assetsError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _assetsError = 'Failed to load marketplace');
    } finally {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = MediaQuery.of(context).size.width >= 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0414) : const Color(0xFFF8FAFC),
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(child: MeshyParticleBackground(isDark: isDark)),
          Positioned.fill(child: _ReactHeroBackground(isDark: isDark)),
          Positioned.fill(
            child: isWeb ? _buildWebMarketplace(context, isDark) : _buildMobileMarketplace(context, isDark),
          ),
          // Mobile-only global section nav as a floating overlay (NOT
          // bottomNavigationBar, so no solid strip is reserved).
          if (!isWeb)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: R2VSectionNav(currentIndex: 3),
            ),
        ],
      ),
    );
  }

  // =====================================================================
  // 🖥 WEB
  // =====================================================================

  Widget _buildWebMarketplace(BuildContext context, bool isDark) {
    final double w = MediaQuery.of(context).size.width;
    final double contentWidth = w > 1180 ? 1180 : w;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildHomeStyleTopBar(context, isDark),
              const SizedBox(height: 18),

              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 22, 16, 32),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMarketHeaderWithCgi(context, isDark),
                            const SizedBox(height: 18),
                            _buildSearchBar(isDark),
                            if (_searchQuery.trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildCreatorResults(isCompact: false, isDark: isDark),
                            ],
                            const SizedBox(height: 16),
                            _buildWebCategoryChips(isDark),
                            const SizedBox(height: 22),
                            Text(
                              "Trending Today",
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildCenteredGrid3Cols(context, isDark),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _selectedAsset == null
                          ? const SizedBox.shrink()
                          : Padding(
                              key: const ValueKey("rightPanel"),
                              padding: const EdgeInsets.only(top: 22, right: 16, bottom: 32),
                              child: SizedBox(
                                width: 360,
                                child: AssetDetailsPanel(
                                  asset: _selectedAsset!,
                                  isDark: isDark,
                                  onClose: () => setState(() => _selectedAsset = null),
                                  onFreeDownload: (asset, format) => _startDownload(context, asset, format: format),
                                  onPaidBuy: (asset) => Navigator.pushNamed(
                                    context,
                                    '/payment',
                                    arguments: asset,
                                  ),
                                ),
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
    );
  }

  Widget _buildCenteredGrid3Cols(BuildContext context, bool isDark) {
    final items = _filteredAssets();
    const gap = 14.0;

    return LayoutBuilder(
      builder: (context, c) {
        final available = c.maxWidth;
        const cols = 3;
        final cardW = (available - (gap * (cols - 1))) / cols;

        if (_loadingAssets) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(color: isDark ? Colors.white : const Color(0xFF8A4FFF)),
            ),
          );
        }

        if (_assetsError != null) {
          return Center(
            child: Column(
              children: [
                Text(
                  _assetsError!,
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _loadAssets,
                  child: const Text("Retry", style: TextStyle(color: Color(0xFF4CC9F0))),
                ),
              ],
            ),
          );
        }

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text("No assets yet", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
            ),
          );
        }

        return Center(
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items.map((item) {
              return SizedBox(
                width: cardW,
                child: AssetCard(
                  name: item.title,
                  author: item.author,
                  creatorId: item.creatorId,
                  likes: item.likes,
                  tag: item.category,
                  styleTag: item.style,
                  posterUrl: item.thumbUrl,
                  priceText: priceLabelEGP(item),
                  width: cardW,
                  isDark: isDark,
                  onTap: () => setState(() => _selectedAsset = item),
                  onAuthorTap: () => Navigator.pushNamed(
                    context,
                    '/profile',
                    arguments: {'userId': item.creatorId, 'username': item.author},
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // =====================================================================
  // 📱 MOBILE
  // =====================================================================

  Widget _buildMobileMarketplace(BuildContext context, bool isDark) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Body flows behind the floating LumaBar (no flat strip); the scroll
      // content reserves the bar's footprint below so nothing hides under it.
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Marketplace", style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1E293B))),
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF1E293B)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28 + R2VSectionNav.barFootprint),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(isDark),
            if (_searchQuery.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildCreatorResults(isCompact: true, isDark: isDark),
            ],
            const SizedBox(height: 14),
            _buildMobileCategoryChips(isDark),
            const SizedBox(height: 18),
            Text(
              "Trending Today",
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_loadingAssets)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: isDark ? Colors.white : const Color(0xFF8A4FFF)),
                ),
              )
            else if (_assetsError != null)
              Center(
                child: Column(
                  children: [
                    Text(_assetsError!, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _loadAssets,
                      child: const Text("Retry", style: TextStyle(color: Color(0xFF4CC9F0))),
                    ),
                  ],
                ),
              )
            else if (_filteredAssets().isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text("No assets yet", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                ),
              )
            else
              Column(
                children: _filteredAssets().map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AssetCard(
                      name: item.title,
                      author: item.author,
                      creatorId: item.creatorId,
                      likes: item.likes,
                      tag: item.category,
                      styleTag: item.style,
                      posterUrl: item.thumbUrl,
                      priceText: priceLabelEGP(item),
                      width: double.infinity,
                      isDark: isDark,
                      onTap: () => _openMobileDetails(item, isDark),
                      onAuthorTap: () => Navigator.pushNamed(
                        context,
                        '/profile',
                        arguments: {'userId': item.creatorId, 'username': item.author},
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _openMobileDetails(MarketplaceAsset item, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: AssetDetailsPanel(
            asset: item,
            isDark: isDark,
            onClose: () => Navigator.pop(context),
            onFreeDownload: (asset, format) => _startDownload(context, asset, format: format),
            onPaidBuy: (asset) => Navigator.pushNamed(
              context,
              '/payment',
              arguments: asset,
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // UI helpers
  // =====================================================================

  Widget _buildHomeStyleTopBar(BuildContext context, bool isDark) {
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
            boxShadow: isDark ? [] : [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 26, color: Color(0xFFBC70FF)),
              const SizedBox(width: 8),
              Text(
                "R2V MARKETPLACE",
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              // ✅ Increased width to 520
              SizedBox(
                  width: 560,
                  child: R2VTopNavTabs(activeIndex: 2, isDark: isDark)),
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

  Widget _buildMarketHeaderWithCgi(BuildContext context, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.20) : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
            boxShadow: isDark ? [] : [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Marketplace",
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 32, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8A4FFF).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _openUploadDialog(context, isDark),
                      icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: const Text("Upload", style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A4FFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Browse trending 3D assets and CGI-ready packs. Mix, match, and export fast.",
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.35, fontSize: 14.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebCategoryChips(bool isDark) {
    return Row(
      children: _categories.map((c) {
        final active = c == selectedCategory;
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: () => setState(() => selectedCategory = c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: active ? const LinearGradient(colors: [Color(0xFF8A4FFF), Color(0xFFBC70FF)]) : null,
                color: active ? null : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04)),
                border: Border.all(color: active ? Colors.transparent : (isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.05))),
              ),
              child: Text(
                c,
                style: TextStyle(color: active ? Colors.white : (isDark ? Colors.white : const Color(0xFF1E293B)), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMobileCategoryChips(bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _categories.map((c) {
          final active = c == selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => setState(() => selectedCategory = c),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: active ? const LinearGradient(colors: [Color(0xFF8A4FFF), Color(0xFFBC70FF)]) : null,
                  color: active ? null : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04)),
                  border: Border.all(color: active ? Colors.transparent : (isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.05))),
                ),
                child: Text(c, style: TextStyle(color: active ? Colors.white : (isDark ? Colors.white : const Color(0xFF1E293B)), fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    // Shared premium glass search field (see lib/widgets/ui/premium_input.dart).
    return PremiumSearchField(
      hintText: "Search objects or creators...",
      onChanged: (value) => setState(() => _searchQuery = value),
    );
  }

  List<MarketplaceAsset> _filteredAssets() {
    final query = _searchQuery.trim().toLowerCase();
    Iterable<MarketplaceAsset> results = _assets;
    if (selectedCategory != "All") {
      results = results.where((a) => a.category == selectedCategory || a.style == selectedCategory);
    }
    if (query.isNotEmpty) {
      results = results.where((a) =>
          a.title.toLowerCase().contains(query) ||
          a.author.toLowerCase().contains(query) ||
          a.tags.any((t) => t.toLowerCase().contains(query)));
    }
    return results.toList();
  }

  List<_CreatorResult> _filteredCreators() {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return [];
    }

    final Map<String, _CreatorResult> results = {};
    for (final asset in _assets) {
      if (asset.creatorId.isEmpty) continue;
      final author = asset.author.trim();
      if (author.isEmpty) continue;
      final existing = results[asset.creatorId];
      if (existing == null) {
        results[asset.creatorId] = _CreatorResult(
          id: asset.creatorId,
          name: author,
          assetCount: 1,
        );
      } else {
        results[asset.creatorId] = existing.copyWith(assetCount: existing.assetCount + 1);
      }
    }

    return results.values
        .where((creator) => creator.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => b.assetCount.compareTo(a.assetCount));
  }

  Widget _buildCreatorResults({required bool isCompact, required bool isDark}) {
    final creators = _filteredCreators();
    if (creators.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Creators",
          style: TextStyle(
            color: isDark ? Colors.white.withOpacity(0.95) : const Color(0xFF1E293B),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final maxPerRow = isCompact ? 1 : max(1, (available / _creatorCardMinWidth).floor());
            final cardWidth = isCompact
                ? available
                : min(_creatorCardMinWidth, (available - 12 * (maxPerRow - 1)) / maxPerRow);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: creators
                  .map(
                    (creator) => _CreatorResultCard(
                      creator: creator,
                      width: cardWidth,
                      isDark: isDark,
                      onTap: () => Navigator.pushNamed(
                        context,
                        '/profile',
                        arguments: {'userId': creator.id, 'username': creator.name},
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  // ignore: unused_element
  static bool isFree(MarketplaceAsset asset) {
    return !asset.isPaid || asset.price <= 0;
  }

  static String priceLabelEGP(MarketplaceAsset asset) {
    final p = asset.price;
    if (p <= 0) return "FREE";
    return "EGP $p";
  }

  Future<void> _startDownload(BuildContext context, MarketplaceAsset asset, {String? format}) async {
    try {
      final url = await r2vMarketplace.downloadAsset(asset.id, format: format);
      if (url.isEmpty) {
        throw Exception('Missing download url');
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start download')),
      );
    }
  }

  Future<void> _openUploadDialog(BuildContext context, bool isDark) async {
    final didUpload = await showDialog<bool>(
      context: context,
      barrierColor: isDark ? Colors.black.withOpacity(0.7) : Colors.black.withOpacity(0.4),
      builder: (_) => _MarketplaceUploadDialog(isDark: isDark),
    );
    if (didUpload == true && mounted) {
      _loadAssets();
    }
  }
}

// =====================================================================
// 🚀 Enhanced Marketplace Upload Dialog
// =====================================================================

class _MarketplaceUploadDialog extends StatefulWidget {
  final bool isDark;
  const _MarketplaceUploadDialog({required this.isDark});

  @override
  State<_MarketplaceUploadDialog> createState() => _MarketplaceUploadDialogState();
}

class _MarketplaceUploadDialogState extends State<_MarketplaceUploadDialog> {
  final GlobalKey _viewerKey = GlobalKey();
  final String _viewerDomId = 'marketplace-model-viewer';
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  Uint8List? _modelBytes;
  String? _modelName;
  String? _modelDataUrl;
  Uint8List? _thumbnailBytes;
  String? _thumbnailName;
  bool _thumbnailCaptured = false;
  bool _isUploading = false;

  String _category = "Objects";
  String _style = "Realistic";

  bool get _canCaptureThumbnail {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['glb', 'gltf', 'obj'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = _modelMimeType(ext);
    setState(() {
      _modelBytes = file.bytes;
      _modelName = file.name;
      _modelDataUrl = Uri.dataFromBytes(file.bytes!, mimeType: mime).toString();
      _thumbnailCaptured = false;
    });
  }

  Future<void> _pickThumbnail() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() {
      _thumbnailBytes = file.bytes;
      _thumbnailName = file.name;
      _thumbnailCaptured = true;
    });
  }

  Future<void> _captureThumbnail() async {
    if (!_canCaptureThumbnail) {
      _showSnack('Capture isn\'t supported on this platform. Please upload a thumbnail image.');
      return;
    }
    if (_modelDataUrl == null) {
      _showSnack('Upload a 3D model first.');
      return;
    }
    if (kIsWeb) {
      final bytes = await captureModelViewerPng(_viewerDomId);
      if (bytes == null) {
        _showSnack('Unable to capture thumbnail.');
        return;
      }
      setState(() {
        _thumbnailBytes = bytes;
        _thumbnailName = 'viewer-thumbnail.png';
        _thumbnailCaptured = true;
      });
      _showSnack('Thumbnail captured from viewer.');
      return;
    }
    final boundary = _viewerKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      _showSnack('Preview not ready for capture.');
      return;
    }
    try {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ImageByteFormat.png);
      if (data == null) {
        _showSnack('Unable to capture thumbnail.');
        return;
      }
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      setState(() {
        _thumbnailBytes = bytes;
        _thumbnailName = 'viewer-thumbnail.png';
        _thumbnailCaptured = true;
      });
      _showSnack('Thumbnail captured from viewer.');
    } catch (_) {
      _showSnack('Thumbnail capture isn’t supported on this platform.');
    }
  }

  String _modelMimeType(String ext) {
    switch (ext) {
      case 'gltf': return 'model/gltf+json';
      case 'obj': return 'model/obj';
      case 'glb':
      default: return 'model/gltf-binary';
    }
  }

  String _thumbnailMimeType(String? name) {
    final lower = (name ?? '').toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _submitUpload() async {
    if (_isUploading) return;
    if (_titleController.text.trim().isEmpty) {
      _showSnack('Add a title for your asset.');
      return;
    }
    if (_modelDataUrl == null || _modelBytes == null) {
      _showSnack('Upload a 3D model to continue.');
      return;
    }
    if (_thumbnailBytes == null) {
      _showSnack('Choose a thumbnail or capture one from the viewer.');
      return;
    }
    final priceInput = _priceController.text.trim();
    final parsedPrice = priceInput.isEmpty ? 0 : int.tryParse(priceInput);
    if (parsedPrice == null || parsedPrice < 0) {
      _showSnack('Enter a valid price.');
      return;
    }

    setState(() => _isUploading = true);
    try {
      final modelName = _modelName ?? 'model.glb';
      final modelExt = modelName.split('.').last.toLowerCase();
      final modelFormat = '.${modelExt.isEmpty ? 'glb' : modelExt}';
      final modelMime = _modelMimeType(modelExt);
      final modelPresign = await r2vMarketplace.presignAssetUpload(
        filename: modelName,
        contentType: modelMime,
        kind: 'model',
      );
      if (modelPresign['url']!.isEmpty || modelPresign['key']!.isEmpty) {
        throw Exception('Missing upload url');
      }
      await r2vMarketplace.uploadToPresignedUrl(
        modelPresign['url']!,
        _modelBytes!,
      );

      final thumbName = _thumbnailName ?? 'thumbnail.png';
      final thumbMime = _thumbnailMimeType(thumbName);
      final thumbPresign = await r2vMarketplace.presignAssetUpload(
        filename: thumbName,
        contentType: thumbMime,
        kind: 'thumb',
      );
      if (thumbPresign['url']!.isEmpty || thumbPresign['key']!.isEmpty) {
        throw Exception('Missing thumbnail upload url');
      }
      await r2vMarketplace.uploadToPresignedUrl(
        thumbPresign['url']!,
        _thumbnailBytes!,
        contentType: thumbMime,
      );

      final asset = await r2vMarketplace.createAsset(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        tags: const [],
        category: _category,
        style: _style,
        isPaid: parsedPrice > 0,
        price: parsedPrice,
        currency: 'egp',
        modelObjectKey: modelPresign['key']!,
        thumbObjectKey: thumbPresign['key']!,
        previewObjectKeys: [modelPresign['key']!],
        metadata: {
          'formats': [modelFormat],
          'format_keys': {modelFormat: modelPresign['key']!},
        },
      );
      await r2vMarketplace.publishAsset(asset.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _showSnack('Asset uploaded to marketplace.');
    } on ApiException catch (e) {
      _showSnack(e.message);
    } on Exception catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      _showSnack(message.isEmpty ? 'Unable to upload asset' : message);
    } catch (_) {
      _showSnack('Unable to upload asset');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: isDark ? Colors.black.withOpacity(0.55) : Colors.white.withOpacity(0.95),
            child: Container(
              width: 720, // Slightly wider for a better 2-column layout feel
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.white),
                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HEADER
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8A4FFF).withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF8A4FFF).withOpacity(0.4)),
                        ),
                        child: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF8A4FFF), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          "Upload to Marketplace",
                          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                            shape: BoxShape.circle,
                            border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent),
                          ),
                          child: Icon(Icons.close, size: 18, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // SCROLLABLE FORM
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. ASSET DETAILS
                          _sectionTitle("1. Asset Details", Icons.description_rounded, isDark),
                          const SizedBox(height: 14),
                          _glassTextField(_titleController, isDark, hint: "Asset Title"),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _glassTextField(_priceController, isDark, hint: "Price (EGP)", isNumber: true),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _glassDropdown(
                                  value: _category,
                                  options: const ["Characters", "Objects", "Vehicles", "Environments", "Stylized", "Realistic"],
                                  onChanged: (v) => setState(() => _category = v ?? _category),
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _glassDropdown(
                                  value: _style,
                                  options: const ["Realistic", "Stylized", "CGI", "Low Poly"],
                                  onChanged: (v) => setState(() => _style = v ?? _style),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _glassTextField(_descriptionController, isDark, hint: "Detailed description...", maxLines: 3),
                          
                          const SizedBox(height: 28),

                          // 2. MEDIA UPLOAD
                          _sectionTitle("2. Media Files", Icons.folder_rounded, isDark),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Model Dropzone
                              Expanded(
                                child: _buildDropzone(
                                  title: "3D Model",
                                  subtitle: ".glb, .gltf, .obj",
                                  filename: _modelName,
                                  icon: Icons.view_in_ar_rounded,
                                  isDark: isDark,
                                  onTap: _pickModel,
                                  isActive: _modelBytes != null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Thumbnail Dropzone
                              Expanded(
                                child: _buildDropzone(
                                  title: "Thumbnail",
                                  subtitle: ".png, .jpg, .webp",
                                  filename: _thumbnailName,
                                  icon: Icons.image_rounded,
                                  isDark: isDark,
                                  onTap: _pickThumbnail,
                                  isActive: _thumbnailBytes != null,
                                  extraAction: _canCaptureThumbnail && _modelBytes != null
                                      ? TextButton.icon(
                                          onPressed: _captureThumbnail,
                                          icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Color(0xFF4CC9F0)),
                                          label: const Text("Capture View", style: TextStyle(color: Color(0xFF4CC9F0), fontSize: 12, fontWeight: FontWeight.w700)),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          // 3. PREVIEW
                          if (_modelBytes != null || _thumbnailBytes != null) ...[
                            _sectionTitle("3. Live Preview", Icons.remove_red_eye_rounded, isDark),
                            const SizedBox(height: 14),
                            _buildPreviewCard(isDark),
                          ]
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // FOOTER ACTIONS
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8A4FFF).withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            )
                          ],
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8A4FFF), Color(0xFFBC70FF)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _submitUpload,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isUploading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Text("Publish Asset", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
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

  Widget _sectionTitle(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isDark ? Colors.white54 : Colors.black45),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(color: isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF1E293B), fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
      ],
    );
  }

  Widget _glassTextField(TextEditingController controller, bool isDark, {required String hint, int maxLines = 1, bool isNumber = false}) {
    return _GlassField(
      controller: controller,
      isDark: isDark,
      hint: hint,
      maxLines: maxLines,
      isNumber: isNumber,
    );
  }

  Widget _glassDropdown({required String value, required List<String> options, required ValueChanged<String?> onChanged, required bool isDark}) {
    return PremiumDropdownField<String>(
      value: value,
      items: options,
      isDark: isDark,
      onChanged: (v) => onChanged(v),
    );
  }

  Widget _buildDropzone({
    required String title,
    required String subtitle,
    required String? filename,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
    required bool isActive,
    Widget? extraAction,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: isActive 
                ? (isDark ? const Color(0xFF8A4FFF).withOpacity(0.15) : const Color(0xFF8A4FFF).withOpacity(0.08)) 
                : (isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02)),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive 
                  ? const Color(0xFF8A4FFF) 
                  : (isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08)),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? Icons.check_circle_rounded : icon, 
                size: 32, 
                color: isActive ? const Color(0xFF8A4FFF) : (isDark ? Colors.white54 : Colors.black38)
              ),
              const SizedBox(height: 12),
              Text(
                isActive ? filename! : title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? (isDark ? Colors.white : const Color(0xFF8A4FFF)) : (isDark ? Colors.white.withOpacity(0.85) : Colors.black87),
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (!isActive) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11.5),
                ),
              ],
              if (extraAction != null) ...[
                const SizedBox(height: 8),
                extraAction,
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.25) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 3D Model View
          Expanded(
            flex: 2,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.5),
                  child: RepaintBoundary(
                    key: _viewerKey,
                    child: _modelDataUrl == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.view_in_ar_rounded, color: isDark ? Colors.white24 : Colors.black12, size: 32),
                                const SizedBox(height: 8),
                                Text("No model uploaded", style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12)),
                              ],
                            ),
                          )
                        : GestureDetector(
                            // ✅ FIX: Consume drag gestures so the parent SingleChildScrollView doesn't scroll!
                            onVerticalDragUpdate: (_) {},
                            onHorizontalDragUpdate: (_) {},
                            child: ModelViewer(
                              key: ValueKey(_modelDataUrl),
                              id: _viewerDomId,
                              src: _modelDataUrl!,
                              backgroundColor: Colors.transparent,
                              cameraControls: true,
                              disableZoom: false,
                              autoRotate: false,
                              // No forced camera framing: model-viewer auto-fits
                              // the model so it fills the frame, and the user is
                              // free to orbit to any angle. Capture View saves
                              // exactly the angle the user chose.
                              environmentImage: "neutral",
                              exposure: 1.0,
                              shadowIntensity: 0.8,
                              shadowSoftness: 1,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Thumbnail View
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("Thumbnail", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
                    if (_thumbnailCaptured) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: const Text("CAPTURED", style: TextStyle(color: Color(0xFF22C55E), fontSize: 9, fontWeight: FontWeight.w800)),
                      )
                    ]
                  ],
                ),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.5),
                      child: _thumbnailBytes == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image_rounded, color: isDark ? Colors.white24 : Colors.black12, size: 28),
                                  const SizedBox(height: 6),
                                  Text("No image", style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11)),
                                ],
                              ),
                            )
                          : Image.memory(_thumbnailBytes!, fit: BoxFit.contain, alignment: Alignment.center),
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
}

class _CreatorResult {
  final String id;
  final String name;
  final int assetCount;

  const _CreatorResult({
    required this.id,
    required this.name,
    required this.assetCount,
  });

  _CreatorResult copyWith({
    String? id,
    String? name,
    int? assetCount,
  }) {
    return _CreatorResult(
      id: id ?? this.id,
      name: name ?? this.name,
      assetCount: assetCount ?? this.assetCount,
    );
  }
}

class _CreatorResultCard extends StatelessWidget {
  final _CreatorResult creator;
  final double width;
  final VoidCallback onTap;
  final bool isDark;

  const _CreatorResultCard({
    required this.creator,
    required this.width,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF8A4FFF).withOpacity(0.4),
                child: Text(
                  creator.name.isNotEmpty ? creator.name.characters.first.toUpperCase() : "?",
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      creator.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${creator.assetCount} item${creator.assetCount == 1 ? "" : "s"}",
                      style: TextStyle(color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white70 : Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class AssetCard extends StatelessWidget {
  final String name;
  final String author;
  final String creatorId;
  final String likes;
  final String tag;
  final String styleTag;
  final String? posterUrl;
  final String priceText;
  final double width;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onAuthorTap;

  const AssetCard({
    super.key,
    required this.name,
    required this.author,
    required this.creatorId,
    required this.likes,
    required this.tag,
    required this.styleTag,
    required this.posterUrl,
    required this.priceText,
    required this.width,
    required this.isDark,
    this.onTap,
    this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCgiLike = styleTag == "Realistic" || tag == "Environments";

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withOpacity(0.24) : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: posterUrl == null || posterUrl!.isEmpty
                    ? Container(
                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                        child: Center(
                          child: Icon(Icons.image_not_supported_rounded, color: isDark ? Colors.white54 : Colors.black26),
                        ),
                      )
                    : PremiumThumbnail(
                        isDark: isDark,
                        image: Image.network(
                          posterUrl!,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) => Container(
                            color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                            child: Center(
                              child: Icon(Icons.image_not_supported_rounded, color: isDark ? Colors.white54 : Colors.black26),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                MiniBadge(
                  text: isCgiLike ? "CGI" : styleTag,
                  accent: isCgiLike ? const Color(0xFF4CC9F0) : const Color(0xFFBC70FF),
                ),
              ],
            ),
            const SizedBox(height: 3),
            MouseRegion(
              cursor: onAuthorTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: GestureDetector(
                onTap: onAuthorTap,
                child: Text(
                  "by $author",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 11,
                    decoration: onAuthorTap != null ? TextDecoration.underline : TextDecoration.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(tag, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 11)),
                const Spacer(),
                Text(
                  priceText,
                  style: TextStyle(
                    color: priceText == "FREE" ? const Color(0xFF22C55E) : (isDark ? Colors.white : const Color(0xFF1E293B)),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.favorite_border_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black54),
                const SizedBox(width: 4),
                Text(likes, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AssetDetailsPanel extends StatefulWidget {
  final MarketplaceAsset asset;
  final bool isDark;
  final VoidCallback onClose;
  final void Function(MarketplaceAsset asset) onPaidBuy;
  final void Function(MarketplaceAsset asset, String? format) onFreeDownload;

  const AssetDetailsPanel({
    super.key,
    required this.asset,
    required this.isDark,
    required this.onClose,
    required this.onPaidBuy,
    required this.onFreeDownload,
  });

  @override
  State<AssetDetailsPanel> createState() => _AssetDetailsPanelState();
}

class _AssetDetailsPanelState extends State<AssetDetailsPanel> {
  bool _expandedOpen = false;
  // Seeded from the backend's per-user state in initState so the heart/bookmark
  // reflect the current user's real liked/saved status after refresh/relogin.
  bool _liked = false;
  bool _saved = false;
  late int _likesCount;
  bool _liking = false;
  bool _saving = false;
  late final List<String> _formats;
  String? _selectedFormat;

  Future<void> _openExpanded(BuildContext context) async {
    setState(() => _expandedOpen = true);

    final model = widget.asset.previewUrl ?? "";
    final poster = widget.asset.thumbUrl ?? "";
    final title = widget.asset.title.isNotEmpty ? widget.asset.title : "Preview";
    final bool isWebWide = MediaQuery.of(context).size.width >= 900;
    final isDark = widget.isDark;

    if (isWebWide) {
      await showDialog(
        context: context,
        barrierColor: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.4),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: _ExpandedViewerShell(title: title, model: model, poster: poster, isDark: isDark),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.90,
            child: _ExpandedViewerShell(title: title, model: model, poster: poster, isDark: isDark),
          ),
        ),
      );
    }

    if (mounted) setState(() => _expandedOpen = false);
  }

  bool _isFree() {
    return !widget.asset.isPaid || widget.asset.price <= 0;
  }

  String _priceLabel() {
    final p = widget.asset.price;
    if (p <= 0) return "FREE";
    return "EGP $p";
  }

  @override
  void initState() {
    super.initState();
    _liked = widget.asset.likedByMe;
    _saved = widget.asset.savedByMe;
    _likesCount = widget.asset.likesCount;
    _formats = _buildFormats(widget.asset);
    _selectedFormat = _formats.isNotEmpty ? _formats.first : null;
  }

  List<String> _buildFormats(MarketplaceAsset asset) {
    final formats = <String>[];
    final rawFormats = asset.metadata['formats'];
    if (rawFormats is List) {
      for (final entry in rawFormats) {
        final normalized = _normalizeFormat(entry?.toString());
        if (normalized != null && !formats.contains(normalized)) {
          formats.add(normalized);
        }
      }
    }
    final fallbackExt = _formatFromKey(asset.modelObjectKey);
    if (formats.isEmpty && fallbackExt != null) {
      formats.add(fallbackExt);
    }
    return formats;
  }

  String? _normalizeFormat(String? raw) {
    final trimmed = raw?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.startsWith('.') ? trimmed : '.$trimmed';
  }

  String? _formatFromKey(String? key) {
    if (key == null || !key.contains('.')) return null;
    final ext = key.split('.').last.trim().toLowerCase();
    if (ext.isEmpty) return null;
    return '.$ext';
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    final nextLiked = !_liked;
    setState(() {
      _liked = nextLiked;
      _likesCount += nextLiked ? 1 : -1;
      _liking = true;
    });
    try {
      if (nextLiked) {
        await r2vMarketplace.likeAsset(widget.asset.id);
      } else {
        await r2vMarketplace.unlikeAsset(widget.asset.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextLiked ? 'Added to likes' : 'Removed from likes')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !nextLiked;
        _likesCount += nextLiked ? -1 : 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = !nextLiked;
        _likesCount += nextLiked ? -1 : 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update like')),
      );
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _toggleSave() async {
    if (_saving) return;
    final nextSaved = !_saved;
    setState(() {
      _saved = nextSaved;
      _saving = true;
    });
    try {
      if (nextSaved) {
        await r2vMarketplace.saveAsset(widget.asset.id);
      } else {
        await r2vMarketplace.unsaveAsset(widget.asset.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextSaved ? 'Saved to your profile' : 'Removed from saved')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saved = !nextSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saved = !nextSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update saved')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Share ────────────────────────────────────────────────────────────────
  // Premium share menu: Copy Link (public marketplace URL) or Send to Follower
  // (shares the same public link via R2V messages, mutual-follow enforced
  // server-side). Never shares a presigned/GLB URL.
  Future<void> _openShareMenu(BuildContext context) async {
    final isDark = widget.isDark;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareMenuSheet(isDark: isDark),
    );
    if (action == null || !context.mounted) return;

    if (action == 'copy') {
      final url = MarketplaceService.shareUrlFor(widget.asset.id);
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied')),
      );
    } else if (action == 'followers') {
      final sent = await showShareToFollowerSheet(
        context,
        assetId: widget.asset.id,
        assetTitle: widget.asset.title,
        isDark: isDark,
      );
      if (sent == null || sent <= 0 || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sent to $sent follower${sent == 1 ? '' : 's'}'),
          action: SnackBarAction(
            label: 'Open Messages',
            onPressed: () => Navigator.of(context).pushNamed('/chat'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.asset.title;
    final author = widget.asset.author;
    final likes = _likesCount.toString();
    final tag = widget.asset.category;
    final style = widget.asset.style;
    final model = widget.asset.previewUrl ?? "";
    final poster = widget.asset.thumbUrl ?? "";
    final description = widget.asset.description.isNotEmpty
        ? widget.asset.description
        : "No description provided.";

    final free = _isFree();
    final priceText = _priceLabel();
    final isDark = widget.isDark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.18) : Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5))],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/profile',
                              arguments: {'userId': widget.asset.creatorId, 'username': author},
                            ),
                            child: Text(
                              "by $author",
                              style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Report is tucked into a subtle overflow menu so it no longer
                  // competes visually with the content.
                  PopupMenuButton<String>(
                    tooltip: "More",
                    color: isDark ? const Color(0xFF1C1528) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    icon: Icon(Icons.more_horiz_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black45),
                    onSelected: (v) {
                      if (v == 'report') {
                        showReportDialog(
                          context,
                          targetType: 'asset',
                          targetId: widget.asset.id,
                          targetLabel: widget.asset.title.isEmpty ? 'asset' : widget.asset.title,
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, size: 18, color: isDark ? Colors.white70 : Colors.black87),
                            const SizedBox(width: 10),
                            Text("Report", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Subtle close.
                  IconButton(
                    onPressed: widget.onClose,
                    tooltip: "Close",
                    splashRadius: 20,
                    icon: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _metaPill(tag, isDark),
                                _metaPill(style, isDark),
                                _metaPill(priceText, isDark, free: free),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Likes as a quiet statistic, not a loud chip.
                          Icon(Icons.favorite_rounded, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                          const SizedBox(width: 4),
                          Text(
                            likes,
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      _sectionLabel("Description", isDark),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          color: isDark ? Colors.white.withOpacity(0.75) : Colors.black.withOpacity(0.7),
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 11,
                              child: Container(
                                color: isDark ? Colors.black.withOpacity(0.18) : Colors.black.withOpacity(0.05),
                                child: _expandedOpen
                                    ? (poster.isEmpty
                                        ? Center(
                                            child: Icon(Icons.image, color: isDark ? Colors.white.withOpacity(0.35) : Colors.black26),
                                          )
                                        : Image.network(
                                            poster,
                                            fit: BoxFit.contain,
                                            alignment: Alignment.center,
                                            errorBuilder: (_, __, ___) => Center(
                                              child: Icon(Icons.image, color: isDark ? Colors.white.withOpacity(0.35) : Colors.black26),
                                            ),
                                          ))
                                    : (model.isEmpty
                                        ? Center(
                                            child: Text(
                                              "Preview unavailable",
                                              style: TextStyle(color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54),
                                            ),
                                          )
                                        : GestureDetector(
                                            // Absorb drags so rotating the model
                                            // doesn't scroll the page behind it.
                                            onVerticalDragUpdate: (_) {},
                                            onHorizontalDragUpdate: (_) {},
                                            child: ModelViewer(
                                              key: ValueKey(model),
                                              src: model,
                                              poster: poster,
                                              backgroundColor: Colors.transparent,
                                              cameraControls: true,
                                              disableZoom: true,
                                              autoRotate: true,
                                              environmentImage: "neutral",
                                              exposure: 1.0,
                                              shadowIntensity: 0.8,
                                              shadowSoftness: 1,
                                            ),
                                          )),
                              ),
                            ),
                            Positioned(
                              right: 10,
                              top: 10,
                              child: InkWell(
                                onTap: () => _openExpanded(context),
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.45),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                                  ),
                                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      _sectionLabel("Format", isDark),
                      const SizedBox(height: 10),
                      if (_formats.isEmpty)
                        Text(
                          "Format info unavailable",
                          style: TextStyle(color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54, fontSize: 12),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _formats
                              .map((f) => InkWell(
                                    onTap: () => setState(() => _selectedFormat = f),
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _selectedFormat == f
                                            ? const Color(0xFF4CC9F0).withOpacity(0.28)
                                            : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04)),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: _selectedFormat == f
                                              ? const Color(0xFF4CC9F0)
                                              : (isDark ? Colors.white.withOpacity(0.12) : Colors.transparent),
                                        ),
                                      ),
                                      child: Text(
                                        f,
                                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Primary action: prominent, full-width.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (free) {
                      widget.onFreeDownload(widget.asset, _selectedFormat);
                    } else {
                      widget.onPaidBuy(widget.asset);
                    }
                  },
                  icon: Icon(free ? Icons.download_rounded : Icons.shopping_bag_rounded, size: 20),
                  label: Text(
                    free ? "Download" : "Buy $priceText",
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: free ? const Color(0xFF22C55E) : const Color(0xFF8A4FFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: isDark ? 0 : 4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Secondary actions: Like / Save / Share.
              Row(
                children: [
                  Expanded(
                    child: _outlineAction(
                      isDark: isDark,
                      icon: _liked ? Icons.favorite : Icons.favorite_border_rounded,
                      label: _liked ? "Liked" : "Like",
                      iconColor: _liked ? const Color(0xFFF72585) : null,
                      onTap: _toggleLike,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _outlineAction(
                      isDark: isDark,
                      icon: _saved ? Icons.bookmark : Icons.bookmark_border_rounded,
                      label: _saved ? "Saved" : "Save",
                      iconColor: _saved ? const Color(0xFF4CC9F0) : null,
                      onTap: _toggleSave,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _outlineAction(
                      isDark: isDark,
                      icon: Icons.ios_share_rounded,
                      label: "Share",
                      onTap: () => _openShareMenu(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Quiet section heading, used for "Description" / "Format".
  static Widget _sectionLabel(String text, bool isDark) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: isDark ? Colors.white.withOpacity(0.55) : Colors.black.withOpacity(0.5),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }

  // Minimal, premium metadata pill (subtle fill, no loud accent).
  static Widget _metaPill(String text, bool isDark, {bool free = false}) {
    final isFreeTag = free && text.toUpperCase() == 'FREE';
    final Color fg = isFreeTag
        ? const Color(0xFF22C55E)
        : (isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF1E293B));
    final Color bg = isFreeTag
        ? const Color(0xFF22C55E).withOpacity(0.14)
        : (isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.04));
    final Color border = isFreeTag
        ? const Color(0xFF22C55E).withOpacity(0.45)
        : (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  // Compact outline action button (Like / Save / Share).
  static Widget _outlineAction({
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final fg = isDark ? Colors.white : const Color(0xFF1E293B);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: iconColor ?? fg),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      ),
    );
  }
}

class _ExpandedViewerShell extends StatelessWidget {
  final String title;
  final String model;
  final String poster;
  final bool isDark;

  const _ExpandedViewerShell({
    required this.title,
    required this.model,
    required this.poster,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.35) : Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5))],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 34,
                        height: 34,
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
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    color: isDark ? Colors.black.withOpacity(0.18) : Colors.black.withOpacity(0.05),
                    child: model.isEmpty
                        ? Center(
                            child: Text(
                              "Preview unavailable",
                              style: TextStyle(color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54),
                            ),
                          )
                        : GestureDetector(
                            // Absorb drags so rotating the model doesn't scroll
                            // the page behind it.
                            onVerticalDragUpdate: (_) {},
                            onHorizontalDragUpdate: (_) {},
                            child: ModelViewer(
                              key: ValueKey("expanded-$model"),
                              src: model,
                              poster: poster,
                              backgroundColor: Colors.transparent,
                              cameraControls: true,
                              disableZoom: false,
                              autoRotate: true,
                              environmentImage: "neutral",
                              exposure: 1.0,
                              shadowIntensity: 0.8,
                              shadowSoftness: 1,
                            ),
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

/// Premium glass dropdown/listbox used by the Upload-to-Marketplace form
/// (Category / Style). Replaces the flat default [DropdownButton] menu with a
/// rounded, soft-shadowed glass panel: width-aligned to the trigger, compact
/// rows with rounded hover/selected highlight, a purple check on the selected
/// item, and tap-outside / Escape to close. Values and onChanged behavior are
/// unchanged from the previous dropdown.
class PremiumDropdownField<T> extends StatefulWidget {
  const PremiumDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
    this.hint,
    this.labelBuilder,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final bool isDark;
  final String? hint;
  final String Function(T)? labelBuilder;

  @override
  State<PremiumDropdownField<T>> createState() => _PremiumDropdownFieldState<T>();
}

class _PremiumDropdownFieldState<T> extends State<PremiumDropdownField<T>> {
  static const Color _accent = Color(0xFF8A4FFF);
  final LayerLink _link = LayerLink();
  final GlobalKey _triggerKey = GlobalKey();
  OverlayEntry? _entry;
  bool _open = false;

  String _label(T v) => widget.labelBuilder?.call(v) ?? v.toString();

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() => _open ? _close() : _openMenu();

  void _close() {
    _removeEntry();
    if (mounted) setState(() => _open = false);
  }

  void _openMenu() {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    if (box == null) return;
    final Size size = box.size;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    final double screenH = MediaQuery.of(context).size.height;
    final double spaceBelow = screenH - (topLeft.dy + size.height);
    // Flip upward when there isn't comfortable room below the trigger.
    final bool openUp = spaceBelow < 220 && topLeft.dy > screenH * 0.45;

    _entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // Tap-outside barrier + Escape-to-close.
            Positioned.fill(
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _close();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _close,
                ),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: openUp ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor: openUp ? Alignment.bottomLeft : Alignment.topLeft,
              offset: Offset(0, openUp ? -6 : 6),
              child: _PremiumDropdownPanel<T>(
                width: size.width,
                items: widget.items,
                selected: widget.value,
                isDark: widget.isDark,
                labelOf: _label,
                onPick: (v) {
                  _close();
                  widget.onChanged(v);
                },
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final baseBorder =
        isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.10);
    final selectedText = _label(widget.value);

    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: AnimatedContainer(
          key: _triggerKey,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _open ? _accent : baseBorder,
              width: _open ? 1.5 : 1,
            ),
            boxShadow: _open
                ? [BoxShadow(color: _accent.withOpacity(0.22), blurRadius: 12, spreadRadius: -2)]
                : const [],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selectedText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: isDark ? Colors.white54 : Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumDropdownPanel<T> extends StatelessWidget {
  const _PremiumDropdownPanel({
    required this.width,
    required this.items,
    required this.selected,
    required this.isDark,
    required this.labelOf,
    required this.onPick,
  });

  final double width;
  final List<T> items;
  final T selected;
  final bool isDark;
  final String Function(T) labelOf;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -6),
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: width,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF15101F).withOpacity(0.92)
                        : Colors.white.withOpacity(0.98),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF8A4FFF).withOpacity(0.30)
                          : Colors.black.withOpacity(0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.45 : 0.18),
                        blurRadius: 24,
                        spreadRadius: -4,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: const Color(0xFF8A4FFF).withOpacity(isDark ? 0.18 : 0.10),
                        blurRadius: 18,
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(maxHeight: 264),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: items
                        .map((item) => _PremiumDropdownRow(
                              label: labelOf(item),
                              isSelected: item == selected,
                              isDark: isDark,
                              onTap: () => onPick(item),
                            ))
                        .toList(),
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

class _PremiumDropdownRow extends StatefulWidget {
  const _PremiumDropdownRow({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_PremiumDropdownRow> createState() => _PremiumDropdownRowState();
}

class _PremiumDropdownRowState extends State<_PremiumDropdownRow> {
  static const Color _accent = Color(0xFF8A4FFF);
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final Color rowColor = _hover
        ? _accent.withOpacity(isDark ? 0.20 : 0.12)
        : (widget.isSelected ? _accent.withOpacity(isDark ? 0.12 : 0.08) : Colors.transparent);
    final Color textColor = widget.isSelected
        ? (isDark ? Colors.white : const Color(0xFF1E293B))
        : (isDark ? Colors.white.withOpacity(0.82) : Colors.black87);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: rowColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (widget.isSelected)
                const Icon(Icons.check_rounded, size: 18, color: _accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-border glass text field for the Upload-to-Marketplace form.
///
/// The app-wide [InputDecorationTheme] sets `filled: true` + an OutlineInputBorder
/// on every field, which—inside this widget's own bordered container—produced a
/// "box inside a box". We defeat that here (filled:false + InputBorder.none for
/// every state) so only the outer container border shows, and add a subtle
/// purple focus glow to keep the premium R2V look.
class _GlassField extends StatefulWidget {
  const _GlassField({
    required this.controller,
    required this.isDark,
    required this.hint,
    this.maxLines = 1,
    this.isNumber = false,
  });

  final TextEditingController controller;
  final bool isDark;
  final String hint;
  final int maxLines;
  final bool isNumber;

  @override
  State<_GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<_GlassField> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() => _focused = _node.hasFocus);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final Color baseBorder =
        isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.10);
    const Color accent = Color(0xFF8A4FFF);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? accent : baseBorder,
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [BoxShadow(color: accent.withOpacity(0.22), blurRadius: 12, spreadRadius: -2)]
            : const [],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        maxLines: widget.maxLines,
        keyboardType: widget.isNumber ? TextInputType.number : TextInputType.text,
        cursorColor: accent,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13.5),
        // Override the global InputDecorationTheme so NO inner fill/border draws.
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hintText: widget.hint,
          hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38, fontSize: 13.5),
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class MiniBadge extends StatelessWidget {
  final String text;
  final Color accent;

  const MiniBadge({super.key, required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.40)),
      ),
      child: Text(
        text,
        style: TextStyle(color: accent, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// =====================================================================
// ✅ Background
// =====================================================================

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
            // Blobs simulating the skew gradients
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
      240, isDark ? const Color(0xFF4895EF) : const Color(0xFF38BDF8), isDark ? 0.14 : 0.10,
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

/// Compact share action menu shown when the Share button is pressed.
/// Returns 'copy' or 'followers' (or null if dismissed).
class _ShareMenuSheet extends StatelessWidget {
  final bool isDark;
  const _ShareMenuSheet({required this.isDark});

  @override
  Widget build(BuildContext context) {
    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required String value,
    }) {
      return ListTile(
        onTap: () => Navigator.of(context).pop(value),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF8A4FFF).withOpacity(isDark ? 0.20 : 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF8A4FFF)),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
            fontSize: 12,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded,
            color: isDark ? Colors.white38 : Colors.black26),
      );
    }

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF120B26).withOpacity(0.96)
                  : Colors.white.withOpacity(0.98),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.black.withOpacity(0.06),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                tile(
                  icon: Icons.link_rounded,
                  title: 'Copy Link',
                  subtitle: 'Copy the public asset link',
                  value: 'copy',
                ),
                tile(
                  icon: Icons.people_alt_rounded,
                  title: 'Share With Friends',
                  subtitle: 'Share via R2V messages',
                  value: 'followers',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
