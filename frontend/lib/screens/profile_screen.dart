import 'dart:ui';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/r2v_api.dart';
import '../api/api_exception.dart';
import '../api/marketplace_service.dart';
import '../api/social_service.dart';
import '../widgets/premium_thumbnail.dart';
import 'widgets/r2v_top_nav_tabs.dart';
import 'widgets/r2v_notification_bell.dart';
import 'explore_screen.dart';

class ProfileScreen extends StatelessWidget {
  final String username;
  final String? userId;
  final String? initialTab;

  const ProfileScreen({super.key, this.username = 'User', this.userId, this.initialTab});

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
            child: isWeb
                ? _WebProfile(username: username, userId: userId, initialTab: initialTab, isDark: isDark)
                : _MobileProfile(username: username, userId: userId, initialTab: initialTab, isDark: isDark),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// WEB VERSION
// ──────────────────────────────────────────────────────────
class _WebProfile extends StatefulWidget {
  final String username;
  final String? userId;
  final String? initialTab;
  final bool isDark;
  const _WebProfile({required this.username, this.userId, this.initialTab, required this.isDark});

  @override
  State<_WebProfile> createState() => _WebProfileState();
}

class _WebProfileState extends State<_WebProfile> {
  ProfileTab _activeTab = ProfileTab.posts;

  late String displayName;
  String displayRole = "Designer · 3D Artist";
  String displayBio = "I create 3D content using AI & real-world photogrammetry tools.";
  Uint8List? avatarBytes;
  String? avatarUrl;
  Map<String, dynamic> _meta = {};
  // ignore: unused_field
  bool _loadingProfile = false;
  bool _loadingFollow = false;
  String? _profileUserId;
  bool _isSelf = true;
  bool _isFollowing = false;
  bool _isFollowedBy = false;
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;

  bool _loadingPosts = false;
  String? _postsError;
  List<MarketplaceAsset> _posts = [];

  bool _loadingSaved = false;
  bool _loadingLiked = false;
  String? _savedError;
  String? _likedError;
  List<MarketplaceAsset> _savedAssets = [];
  List<MarketplaceAsset> _likedAssets = [];

  Future<void> _openAssetPreview(MarketplaceAsset asset) async {
    await _showAssetPreview(context, asset);
    if (!mounted) return;
    // The preview lets the user like/unlike (and save/unsave). Re-sync the
    // active collection tab so an unliked asset leaves the Liked tab (and an
    // unsaved one leaves the Saved tab) without a manual refresh.
    if (_activeTab == ProfileTab.liked) {
      await _loadLiked();
    } else if (_activeTab == ProfileTab.saved) {
      await _loadSaved();
    }
  }

  void _applyInitialTab(String? tab) {
    final parsed = _parseProfileTab(tab);
    if (!_isSelf || parsed == null) return;
    _activeTab = parsed;
  }

  Future<void> _loadInitialTabAssets() async {
    if (!_isSelf) return;
    if (_activeTab == ProfileTab.saved) {
      await _loadSaved();
    } else if (_activeTab == ProfileTab.liked) {
      await _loadLiked();
    }
  }

  @override
  void initState() {
    super.initState();
    displayName = widget.username;
    _profileUserId = _normalizeUserId(widget.userId);
    _isSelf = _profileUserId == null;
    _applyInitialTab(widget.initialTab);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadProfile();
    await _loadPosts();
    await _loadInitialTabAssets();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final profile = await r2vProfile.me();
      final targetUserId = _normalizeUserId(widget.userId) ?? profile.id;

      SocialProfile? socialProfile;
      try {
        socialProfile = await r2vSocial.getProfile(targetUserId);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }

      if (!mounted) return;
      setState(() {
        _profileUserId = targetUserId;
        _isSelf = (socialProfile?.isSelf ?? false) || profile.id == targetUserId;
        _isFollowing = socialProfile?.isFollowing ?? false;
        _isFollowedBy = socialProfile?.isFollowedBy ?? false;
        _postsCount = socialProfile?.posts ?? _postsCount;
        _followersCount = socialProfile?.followers ?? _followersCount;
        _followingCount = socialProfile?.following ?? _followingCount;

        displayName = (socialProfile?.username.isNotEmpty ?? false) ? socialProfile!.username : displayName;
        displayBio = socialProfile?.bio ?? displayBio;
        avatarUrl = socialProfile?.avatarUrl ?? avatarUrl;
        avatarBytes = _decodeAvatar(socialProfile?.avatarUrl) ?? avatarBytes;

        if (_isSelf) {
          displayName = profile.username.isNotEmpty ? profile.username : displayName;
          displayBio = profile.bio ?? displayBio;
          _meta = profile.meta;
          displayRole = profile.meta['role']?.toString() ?? displayRole;
          avatarUrl = profile.avatarUrl ?? avatarUrl;
          avatarBytes = _decodeAvatar(profile.avatarUrl) ?? avatarBytes;
        }

        if (!_isSelf) _activeTab = ProfileTab.posts;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 404) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load profile')));
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadPosts() async {
    if (!_isSelf && (_profileUserId == null || _profileUserId!.isEmpty)) return;
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    try {
      final assets = _isSelf
          ? await r2vMarketplace.listMyAssets()
          : await r2vMarketplace.listUserAssets(_profileUserId!);
      if (!mounted) return;
      setState(() {
        _posts = assets;
        _postsCount = assets.length;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _postsError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _postsError = _isSelf ? 'Failed to load your posts' : 'Failed to load posts');
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  Future<void> _loadSaved() async {
    if (!_isSelf) return;
    setState(() {
      _loadingSaved = true;
      _savedError = null;
    });
    try {
      final assets = await r2vMarketplace.listSavedAssets();
      if (!mounted) return;
      setState(() => _savedAssets = assets);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _savedError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _savedError = 'Failed to load saved assets');
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  Future<void> _loadLiked() async {
    if (!_isSelf) return;
    setState(() {
      _loadingLiked = true;
      _likedError = null;
    });
    try {
      final assets = await r2vMarketplace.listLikedAssets();
      if (!mounted) return;
      setState(() => _likedAssets = assets);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _likedError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _likedError = 'Failed to load liked assets');
    } finally {
      if (mounted) setState(() => _loadingLiked = false);
    }
  }

  Future<void> _confirmDeleteAsset(MarketplaceAsset asset) async {
    if (!_isSelf) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1A1B20) : Colors.white,
        title: Text('Delete asset?', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
        content: Text('This will remove the asset from your profile and marketplace.', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black54))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (shouldDelete != true) return;

    try {
      await r2vMarketplace.deleteAsset(asset.id);
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((item) => item.id == asset.id);
        _postsCount = _posts.length;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset deleted')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete asset')));
    }
  }

  Uint8List? _decodeAvatar(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!raw.startsWith('data:image')) return null;
    final parts = raw.split(',');
    if (parts.length < 2) return null;
    try {
      return base64Decode(parts.last);
    } catch (_) {
      return null;
    }
  }

  String? _normalizeUserId(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'null') return null;
    return trimmed;
  }

  Future<void> _openEditProfileDialog() async {
    if (!_isSelf) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) {
        return _EditProfileDialog(
          initialName: displayName,
          initialRole: displayRole,
          initialBio: displayBio,
          initialAvatar: avatarBytes,
          onSave: _saveProfile,
          isDark: widget.isDark,
        );
      },
    );
  }

  Future<void> _saveProfile(String name, String role, String bio, Uint8List? bytes) async {
    if (!_isSelf) return;
    final nextMeta = Map<String, dynamic>.from(_meta);
    nextMeta['role'] = role;
    final avatarDataUrl = bytes == null ? avatarUrl : _toDataUrl(bytes);

    setState(() => _loadingProfile = true);
    try {
      final updated = await r2vProfile.update(
        username: name,
        bio: bio,
        avatarUrl: avatarDataUrl,
        meta: nextMeta,
      );
      if (!mounted) return;
      setState(() {
        displayName = updated.username;
        displayBio = updated.bio ?? displayBio;
        displayRole = updated.meta['role']?.toString() ?? displayRole;
        _meta = updated.meta;
        avatarUrl = updated.avatarUrl;
        avatarBytes = _decodeAvatar(updated.avatarUrl) ?? bytes;
      });
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update profile')));
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  String _toDataUrl(Uint8List bytes) {
    final encoded = base64Encode(bytes);
    return 'data:image/png;base64,$encoded';
  }

  Future<void> _toggleFollow() async {
    if (_loadingFollow || _isSelf || _profileUserId == null) return;
    setState(() => _loadingFollow = true);
    try {
      if (_isFollowing) {
        await r2vSocial.unfollow(_profileUserId!);
      } else {
        await r2vSocial.follow(_profileUserId!);
      }
      if (!mounted) return;
      setState(() {
        _isFollowing = !_isFollowing;
        _followersCount += _isFollowing ? 1 : -1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFollowing ? 'Unable to unfollow user' : 'Unable to follow user')),
      );
    } finally {
      if (mounted) setState(() => _loadingFollow = false);
    }
  }

  void _openMessage() {
    if (_isSelf || _profileUserId == null) return;
    Navigator.pushNamed(context, '/chat', arguments: {'userId': _profileUserId});
  }

  void _openFollowersFollowing(BuildContext context, {required int initialIndex}) {
    final targetUserId = _profileUserId;
    if (targetUserId == null || targetUserId.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: _FollowersFollowingPanel(
          targetUserId: targetUserId,
          initialIndex: initialIndex,
          isDark: widget.isDark,
          onOpenProfile: (u) {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(username: u.username, userId: u.userId)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final double contentWidth = w > 1180 ? 1180 : w;
    final isDark = widget.isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth),
            child: Column(
              children: [
                const SizedBox(height: 14),
                _GlassTopBar(
                  activeIndex: 0,
                  isDark: isDark,
                  onProfile: () {},
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _glassProfileHeader(context, isDark),
                        const SizedBox(height: 16),
                        _glassTabsRow(isDark),
                        const SizedBox(height: 14),
                        _glassGrid(isDark),
                      ],
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

  Widget _glassProfileHeader(BuildContext context, bool isDark) {
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
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatar(90, isDark),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(displayRole, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.78) : Colors.black87, fontSize: 14.5)),
                    const SizedBox(height: 6),
                    Text(displayBio, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.62) : Colors.black54, fontSize: 13)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _PillTag(icon: Icons.auto_awesome_rounded, label: "AI Creator", isDark: isDark),
                        _PillTag(icon: Icons.photo_camera_back_rounded, label: "Photogrammetry", isDark: isDark),
                        _PillTag(icon: Icons.view_in_ar_rounded, label: "AR/VR", isDark: isDark),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              _stat('$_postsCount', "Posts", isDark: isDark),
              const SizedBox(width: 26),
              _stat('$_followersCount', "Followers", onTap: () => _openFollowersFollowing(context, initialIndex: 0), isDark: isDark),
              const SizedBox(width: 26),
              _stat('$_followingCount', "Following", onTap: () => _openFollowersFollowing(context, initialIndex: 1), isDark: isDark),
              const SizedBox(width: 18),
              
              IconButton(
                onPressed: () => Navigator.pushNamed(context, '/analysis'),
                icon: const Icon(Icons.analytics_rounded, color: Color(0xFF4CC9F0), size: 28),
                tooltip: "View Analysis",
              ),
              const SizedBox(width: 12),

              // Mutual-follow rule: Message is only available when both users
              // follow each other (matches the backend DM restriction).
              if (!_isSelf && _profileUserId != null && _isFollowing && _isFollowedBy) ...[
                OutlinedButton.icon(
                  onPressed: _openMessage,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text("Message"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8A4FFF),
                    side: const BorderSide(color: Color(0xFF8A4FFF)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
                const SizedBox(width: 12),
              ],

              _isSelf
                  ? ElevatedButton.icon(
                      onPressed: _openEditProfileDialog,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text("Edit Profile"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A4FFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: isDark ? 0 : 4,
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _loadingFollow ? null : _toggleFollow,
                      icon: Icon(_isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded, size: 18),
                      label: Text(_isFollowing ? "Following" : "Follow"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFollowing ? (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05)) : const Color(0xFF8A4FFF),
                        foregroundColor: _isFollowing ? (isDark ? Colors.white : Colors.black87) : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: isDark ? 0 : 4,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassTabsRow(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.16) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              _TabChip(
                label: "Posts",
                active: _activeTab == ProfileTab.posts,
                onTap: () => setState(() => _activeTab = ProfileTab.posts),
                isDark: isDark,
              ),
              if (_isSelf) ...[
                const SizedBox(width: 10),
                _TabChip(
                  label: "Saved",
                  active: _activeTab == ProfileTab.saved,
                  onTap: () {
                    setState(() => _activeTab = ProfileTab.saved);
                    if (_savedAssets.isEmpty && !_loadingSaved) _loadSaved();
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _TabChip(
                  label: "Liked",
                  active: _activeTab == ProfileTab.liked,
                  onTap: () {
                    setState(() => _activeTab = ProfileTab.liked);
                    if (_likedAssets.isEmpty && !_loadingLiked) _loadLiked();
                  },
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassGrid(bool isDark) {
    if (_activeTab == ProfileTab.posts) {
      if (_loadingPosts) {
        return Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(color: isDark ? Colors.white : const Color(0xFFBC70FF))));
      }
      if (_postsError != null) {
        return Center(
          child: Column(
            children: [
              Text(_postsError!, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 10),
              TextButton(onPressed: _loadPosts, child: const Text("Retry", style: TextStyle(color: Color(0xFF4CC9F0)))),
            ],
          ),
        );
      }
      if (_posts.isEmpty) {
        return _emptyTabState(title: "No posts yet.", onAction: () => Navigator.pushNamed(context, '/explore'), isDark: isDark);
      }
      return Wrap(spacing: 14, runSpacing: 14, children: _posts.map((asset) => _postTile(asset, isDark: isDark, showDelete: _isSelf)).toList());
    }

    if (_activeTab == ProfileTab.saved) {
      return _assetTabGrid(assets: _savedAssets, loading: _loadingSaved, error: _savedError, emptyTitle: "No saved assets yet.", isDark: isDark);
    }

    return _assetTabGrid(assets: _likedAssets, loading: _loadingLiked, error: _likedError, emptyTitle: "No liked assets yet.", isDark: isDark);
  }

  Widget _assetTabGrid({required List<MarketplaceAsset> assets, required bool loading, required String? error, required String emptyTitle, required bool isDark}) {
    if (loading) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(color: isDark ? Colors.white : const Color(0xFFBC70FF))));
    }
    if (error != null) {
      return Center(
        child: Column(
          children: [
            Text(error, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(height: 10),
            TextButton(onPressed: _activeTab == ProfileTab.saved ? _loadSaved : _loadLiked, child: const Text("Retry", style: TextStyle(color: Color(0xFF4CC9F0)))),
          ],
        ),
      );
    }
    if (assets.isEmpty) {
      return _emptyTabState(title: emptyTitle, onAction: () => Navigator.pushNamed(context, '/explore'), isDark: isDark);
    }
    return Wrap(spacing: 14, runSpacing: 14, children: assets.map((asset) => _postTile(asset, isDark: isDark)).toList());
  }

  Widget _postTile(MarketplaceAsset asset, {bool showDelete = false, required bool isDark}) {
    final thumb = asset.thumbUrl ?? '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAssetPreview(asset),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 240, height: 240,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.18) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: thumb.isEmpty
                      ? Container(color: isDark ? Colors.black.withOpacity(0.12) : Colors.black.withOpacity(0.04), child: Icon(Icons.image_rounded, color: isDark ? Colors.white30 : Colors.black12, size: 60))
                      : PremiumThumbnail(
                          isDark: isDark,
                          image: Image.network(
                            thumb, fit: BoxFit.contain, alignment: Alignment.center,
                            errorBuilder: (_, __, ___) => Container(color: isDark ? Colors.black.withOpacity(0.12) : Colors.black.withOpacity(0.04), child: Icon(Icons.image_rounded, color: isDark ? Colors.white30 : Colors.black12, size: 60)),
                          ),
                        ),
                ),
                Positioned(
                  left: 10, right: 10, bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      asset.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
                if (showDelete)
                  Positioned(
                    top: 10, right: 10,
                    child: InkWell(
                      onTap: () => _confirmDeleteAsset(asset),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 16),
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

  Widget _stat(String value, String label, {VoidCallback? onTap, required bool isDark}) {
    final content = Column(
      children: [
        Text(value, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.70) : Colors.black54, fontSize: 12)),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: content),
    );
  }

  Widget _avatar(double size, bool isDark) {
    final avatar = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.05),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.22) : Colors.white, width: 2),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipOval(
              child: avatarBytes != null
                  ? Image.memory(avatarBytes!, fit: BoxFit.cover)
                  : (avatarUrl != null && avatarUrl!.isNotEmpty && !avatarUrl!.startsWith('data:image')
                      ? Image.network(avatarUrl!, fit: BoxFit.cover)
                      : Icon(Icons.person, size: size*0.5, color: isDark ? Colors.white54 : Colors.black26)),
            ),
          ),
          if (_isSelf)
            Positioned(
              right: 4, bottom: 4,
              child: Container(
                width: size * 0.28, height: size * 0.28,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                ),
                child: Icon(Icons.camera_alt_rounded, color: Colors.white, size: size * 0.14),
              ),
            ),
        ],
      ),
    );
    if (!_isSelf) return avatar;
    return GestureDetector(onTap: _openEditProfileDialog, child: avatar);
  }

  Widget _emptyTabState({required String title, required VoidCallback onAction, required bool isDark}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.18) : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.white),
      ),
      child: Column(
        children: [
          Icon(Icons.bookmark_border_rounded, color: isDark ? Colors.white.withOpacity(0.5) : Colors.black26, size: 40),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onAction,
            child: const Text("Browse Marketplace", style: TextStyle(color: Color(0xFF4CC9F0))),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// MOBILE VERSION
// ──────────────────────────────────────────────────────────
class _MobileProfile extends StatefulWidget {
  final String username;
  final String? userId;
  final String? initialTab;
  final bool isDark;
  const _MobileProfile({required this.username, this.userId, this.initialTab, required this.isDark});

  @override
  State<_MobileProfile> createState() => _MobileProfileState();
}

class _MobileProfileState extends State<_MobileProfile> {
  late String displayName;
  String displayRole = "3D Artist · Designer";
  String displayBio = "Building the future of AR/VR assets using AI + photogrammetry.";
  Uint8List? avatarBytes;
  String? avatarUrl;
  Map<String, dynamic> _meta = {};
  // ignore: unused_field
  bool _loadingProfile = false;
  bool _loadingFollow = false;
  String? _profileUserId;
  bool _isSelf = true;
  bool _isFollowing = false;
  bool _isFollowedBy = false;
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;

  ProfileTab _activeTab = ProfileTab.posts;
  bool _loadingPosts = false;
  String? _postsError;
  List<MarketplaceAsset> _posts = [];

  bool _loadingSaved = false;
  bool _loadingLiked = false;
  String? _savedError;
  String? _likedError;
  List<MarketplaceAsset> _savedAssets = [];
  List<MarketplaceAsset> _likedAssets = [];

  Future<void> _openAssetPreview(MarketplaceAsset asset) async {
    await _showAssetPreview(context, asset);
    if (!mounted) return;
    // The preview lets the user like/unlike (and save/unsave). Re-sync the
    // active collection tab so an unliked asset leaves the Liked tab (and an
    // unsaved one leaves the Saved tab) without a manual refresh.
    if (_activeTab == ProfileTab.liked) {
      await _loadLiked();
    } else if (_activeTab == ProfileTab.saved) {
      await _loadSaved();
    }
  }

  void _applyInitialTab(String? tab) {
    final parsed = _parseProfileTab(tab);
    if (!_isSelf || parsed == null) return;
    _activeTab = parsed;
  }

  Future<void> _loadInitialTabAssets() async {
    if (!_isSelf) return;
    if (_activeTab == ProfileTab.saved) {
      await _loadSaved();
    } else if (_activeTab == ProfileTab.liked) {
      await _loadLiked();
    }
  }

  @override
  void initState() {
    super.initState();
    displayName = widget.username;
    _profileUserId = _normalizeUserId(widget.userId);
    _isSelf = _profileUserId == null;
    _applyInitialTab(widget.initialTab);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadProfile();
    await _loadPosts();
    await _loadInitialTabAssets();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final profile = await r2vProfile.me();
      final targetUserId = _normalizeUserId(widget.userId) ?? profile.id;

      SocialProfile? socialProfile;
      try {
        socialProfile = await r2vSocial.getProfile(targetUserId);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }

      if (!mounted) return;
      setState(() {
        _profileUserId = targetUserId;
        _isSelf = (socialProfile?.isSelf ?? false) || profile.id == targetUserId;
        _isFollowing = socialProfile?.isFollowing ?? false;
        _isFollowedBy = socialProfile?.isFollowedBy ?? false;
        _postsCount = socialProfile?.posts ?? _postsCount;
        _followersCount = socialProfile?.followers ?? _followersCount;
        _followingCount = socialProfile?.following ?? _followingCount;

        displayName = (socialProfile?.username.isNotEmpty ?? false) ? socialProfile!.username : displayName;
        displayBio = socialProfile?.bio ?? displayBio;
        avatarUrl = socialProfile?.avatarUrl ?? avatarUrl;
        avatarBytes = _decodeAvatar(socialProfile?.avatarUrl) ?? avatarBytes;

        if (_isSelf) {
          displayName = profile.username.isNotEmpty ? profile.username : displayName;
          displayBio = profile.bio ?? displayBio;
          _meta = profile.meta;
          displayRole = profile.meta['role']?.toString() ?? displayRole;
          avatarUrl = profile.avatarUrl ?? avatarUrl;
          avatarBytes = _decodeAvatar(profile.avatarUrl) ?? avatarBytes;
        }

        if (!_isSelf) _activeTab = ProfileTab.posts;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 404) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load profile')));
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadPosts() async {
    if (!_isSelf && (_profileUserId == null || _profileUserId!.isEmpty)) return;
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    try {
      final assets = _isSelf
          ? await r2vMarketplace.listMyAssets()
          : await r2vMarketplace.listUserAssets(_profileUserId!);
      if (!mounted) return;
      setState(() {
        _posts = assets;
        _postsCount = assets.length;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _postsError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _postsError = _isSelf ? 'Failed to load your posts' : 'Failed to load posts');
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  Future<void> _loadSaved() async {
    if (!_isSelf) return;
    setState(() {
      _loadingSaved = true;
      _savedError = null;
    });
    try {
      final assets = await r2vMarketplace.listSavedAssets();
      if (!mounted) return;
      setState(() => _savedAssets = assets);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _savedError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _savedError = 'Failed to load saved assets');
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  Future<void> _loadLiked() async {
    if (!_isSelf) return;
    setState(() {
      _loadingLiked = true;
      _likedError = null;
    });
    try {
      final assets = await r2vMarketplace.listLikedAssets();
      if (!mounted) return;
      setState(() => _likedAssets = assets);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _likedError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _likedError = 'Failed to load liked assets');
    } finally {
      if (mounted) setState(() => _loadingLiked = false);
    }
  }

  Uint8List? _decodeAvatar(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!raw.startsWith('data:image')) return null;
    final parts = raw.split(',');
    if (parts.length < 2) return null;
    try {
      return base64Decode(parts.last);
    } catch (_) {
      return null;
    }
  }

  String? _normalizeUserId(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'null') return null;
    return trimmed;
  }

  Future<void> _openEditProfileDialog() async {
    if (!_isSelf) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) {
        return _EditProfileDialog(
          initialName: displayName,
          initialRole: displayRole,
          initialBio: displayBio,
          initialAvatar: avatarBytes,
          onSave: _saveProfile,
          isDark: widget.isDark,
        );
      },
    );
  }

  Future<void> _saveProfile(String name, String role, String bio, Uint8List? bytes) async {
    if (!_isSelf) return;
    final nextMeta = Map<String, dynamic>.from(_meta);
    nextMeta['role'] = role;
    final avatarDataUrl = bytes == null ? avatarUrl : _toDataUrl(bytes);

    setState(() => _loadingProfile = true);
    try {
      final updated = await r2vProfile.update(
        username: name,
        bio: bio,
        avatarUrl: avatarDataUrl,
        meta: nextMeta,
      );
      if (!mounted) return;
      setState(() {
        displayName = updated.username;
        displayBio = updated.bio ?? displayBio;
        displayRole = updated.meta['role']?.toString() ?? displayRole;
        _meta = updated.meta;
        avatarUrl = updated.avatarUrl;
        avatarBytes = _decodeAvatar(updated.avatarUrl) ?? bytes;
      });
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update profile')));
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  String _toDataUrl(Uint8List bytes) => 'data:image/png;base64,${base64Encode(bytes)}';

  Future<void> _toggleFollow() async {
    if (_loadingFollow || _isSelf || _profileUserId == null) return;
    setState(() => _loadingFollow = true);
    try {
      if (_isFollowing) {
        await r2vSocial.unfollow(_profileUserId!);
      } else {
        await r2vSocial.follow(_profileUserId!);
      }
      if (!mounted) return;
      setState(() {
        _isFollowing = !_isFollowing;
        _followersCount += _isFollowing ? 1 : -1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFollowing ? 'Unable to unfollow user' : 'Unable to follow user')),
      );
    } finally {
      if (mounted) setState(() => _loadingFollow = false);
    }
  }

  void _openMessage() {
    if (_isSelf || _profileUserId == null) return;
    Navigator.pushNamed(context, '/chat', arguments: {'userId': _profileUserId});
  }

  void _openFollowersFollowing(BuildContext context, {required int initialIndex}) {
    final targetUserId = _profileUserId;
    if (targetUserId == null || targetUserId.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(12),
        child: _FollowersFollowingPanel(
          targetUserId: targetUserId,
          initialIndex: initialIndex,
          isSheet: true,
          isDark: widget.isDark,
          onOpenProfile: (u) {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(username: u.username, userId: u.userId)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Profile", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF1E293B)),
        actions: [
          // Mobile notification bell — only on your own profile, top-right
          // header. Bottom LumaBar nav stays unchanged.
          if (_isSelf) ...[
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Center(child: R2VNotificationBell(isDark: isDark, size: 36)),
            ),
          ],
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/analysis'),
            icon: const Icon(Icons.analytics_rounded, color: Color(0xFF4CC9F0)),
            tooltip: "Analytics",
          ),
          // Mutual-follow rule: Message only when both users follow each other.
          if (!_isSelf && _profileUserId != null && _isFollowing && _isFollowedBy)
            IconButton(
              onPressed: _openMessage,
              icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF8A4FFF)),
              tooltip: "Message",
            ),
          if (_isSelf)
            IconButton(
              onPressed: _openEditProfileDialog,
              icon: const Icon(Icons.edit_rounded, color: Color(0xFFBC70FF)),
              tooltip: "Edit",
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _glassMobileHeader(isDark),
            const SizedBox(height: 14),
            _glassMobileTabs(isDark),
            const SizedBox(height: 14),
            _mobileGrid(isDark),
          ],
        ),
      ),
    );
  }

  Widget _glassMobileHeader(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.18) : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Column(
            children: [
              _avatar(110, isDark),
              const SizedBox(height: 12),
              Text(displayName, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(displayRole, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.75) : Colors.black87, fontSize: 13)),
              const SizedBox(height: 8),
              Text(
                displayBio,
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white.withOpacity(0.62) : Colors.black54, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MStat(value: '$_postsCount', label: "Posts", isDark: isDark),
                  _MStat(value: '$_followersCount', label: "Followers", onTap: () => _openFollowersFollowing(context, initialIndex: 0), isDark: isDark),
                  _MStat(value: '$_followingCount', label: "Following", onTap: () => _openFollowersFollowing(context, initialIndex: 1), isDark: isDark),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: _isSelf
                    ? ElevatedButton(
                        onPressed: _openEditProfileDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8A4FFF),
                          foregroundColor: Colors.white,
                          elevation: isDark ? 0 : 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.w700)),
                      )
                    : ElevatedButton.icon(
                        onPressed: _loadingFollow ? null : _toggleFollow,
                        icon: Icon(_isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded, size: 18),
                        label: Text(_isFollowing ? "Following" : "Follow"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFollowing ? (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05)) : const Color(0xFF8A4FFF),
                          foregroundColor: _isFollowing ? (isDark ? Colors.white : Colors.black87) : Colors.white,
                          elevation: isDark ? 0 : 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassMobileTabs(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.14) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.white),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              _TabChip(label: "Posts", active: _activeTab == ProfileTab.posts, onTap: () => setState(() => _activeTab = ProfileTab.posts), isDark: isDark),
              if (_isSelf) ...[
                const SizedBox(width: 10),
                _TabChip(
                  label: "Saved",
                  active: _activeTab == ProfileTab.saved,
                  onTap: () {
                    setState(() => _activeTab = ProfileTab.saved);
                    if (_savedAssets.isEmpty && !_loadingSaved) _loadSaved();
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _TabChip(
                  label: "Liked",
                  active: _activeTab == ProfileTab.liked,
                  onTap: () {
                    setState(() => _activeTab = ProfileTab.liked);
                    if (_likedAssets.isEmpty && !_loadingLiked) _loadLiked();
                  },
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileGrid(bool isDark) {
    if (_activeTab == ProfileTab.posts) {
      if (_loadingPosts) {
        return Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: isDark ? Colors.white : const Color(0xFFBC70FF))));
      }
      if (_postsError != null) {
        return Center(
          child: Column(
            children: [
              Text(_postsError!, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 10),
              TextButton(onPressed: _loadPosts, child: const Text("Retry", style: TextStyle(color: Color(0xFF4CC9F0)))),
            ],
          ),
        );
      }
      if (_posts.isEmpty) {
        return _mobileEmptyState(title: "No posts yet.", onAction: () => Navigator.pushNamed(context, '/explore'), isDark: isDark);
      }
      return _mobileAssetGrid(_posts, isDark: isDark, showDelete: _isSelf);
    }

    if (_activeTab == ProfileTab.saved) {
      return _mobileAssetTabGrid(
        assets: _savedAssets,
        loading: _loadingSaved,
        error: _savedError,
        emptyTitle: "No saved assets yet.",
        isDark: isDark,
      );
    }

    return _mobileAssetTabGrid(
      assets: _likedAssets,
      loading: _loadingLiked,
      error: _likedError,
      emptyTitle: "No liked assets yet.",
      isDark: isDark,
    );
  }

  Widget _mobileAssetTabGrid({
    required List<MarketplaceAsset> assets,
    required bool loading,
    required String? error,
    required String emptyTitle,
    required bool isDark,
  }) {
    if (loading) {
      return Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: isDark ? Colors.white : const Color(0xFFBC70FF))));
    }
    if (error != null) {
      return Center(
        child: Column(
          children: [
            Text(error, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _activeTab == ProfileTab.saved ? _loadSaved : _loadLiked,
              child: const Text("Retry", style: TextStyle(color: Color(0xFF4CC9F0))),
            ),
          ],
        ),
      );
    }
    if (assets.isEmpty) {
      return _mobileEmptyState(title: emptyTitle, onAction: () => Navigator.pushNamed(context, '/explore'), isDark: isDark);
    }
    return _mobileAssetGrid(assets, isDark: isDark);
  }

  Widget _mobileAssetGrid(List<MarketplaceAsset> assets, {bool showDelete = false, required bool isDark}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: assets.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, i) {
        final asset = assets[i];
        final thumb = asset.thumbUrl ?? '';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openAssetPreview(asset),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.14) : Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.white),
                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: thumb.isEmpty
                          ? Icon(Icons.image_rounded, color: isDark ? Colors.white30 : Colors.black12)
                          : PremiumThumbnail(
                              isDark: isDark,
                              image: Image.network(
                                thumb,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                errorBuilder: (_, __, ___) => Icon(Icons.image_rounded, color: isDark ? Colors.white30 : Colors.black12),
                              ),
                            ),
                    ),
                    if (showDelete)
                      Positioned(
                        top: 6, right: 6,
                        child: InkWell(
                          onTap: () async {
                            _confirmDeleteAsset(asset);
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: const Icon(Icons.delete_outline, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteAsset(MarketplaceAsset asset) async {
    if (!_isSelf) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1A1B20) : Colors.white,
        title: Text('Delete asset?', style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
        content: Text('This will remove the asset from your profile and marketplace.', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black54))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (shouldDelete != true) return;

    try {
      await r2vMarketplace.deleteAsset(asset.id);
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((item) => item.id == asset.id);
        _postsCount = _posts.length;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset deleted')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete asset')));
    }
  }


  Widget _mobileEmptyState({required String title, required VoidCallback onAction, required bool isDark}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.14) : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.white),
      ),
      child: Column(
        children: [
          Icon(Icons.bookmark_border_rounded, color: isDark ? Colors.white.withOpacity(0.5) : Colors.black26, size: 32),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextButton(onPressed: onAction, child: const Text("Browse Marketplace", style: TextStyle(color: Color(0xFF4CC9F0)))),
        ],
      ),
    );
  }

  Widget _avatar(double size, bool isDark) {
    final avatar = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.05),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.22) : Colors.white, width: 2),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipOval(
              child: avatarBytes != null
                  ? Image.memory(avatarBytes!, fit: BoxFit.cover)
                  : (avatarUrl != null && avatarUrl!.isNotEmpty && !avatarUrl!.startsWith('data:image')
                      ? Image.network(avatarUrl!, fit: BoxFit.cover)
                      : Icon(Icons.person, size: size*0.5, color: isDark ? Colors.white54 : Colors.black26)),
            ),
          ),
          if (_isSelf)
            Positioned(
              right: 4, bottom: 4,
              child: Container(
                width: size * 0.28, height: size * 0.28,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                ),
                child: Icon(Icons.camera_alt_rounded, color: Colors.white, size: size * 0.14),
              ),
            ),
        ],
      ),
    );
    if (!_isSelf) return avatar;
    return GestureDetector(onTap: _openEditProfileDialog, child: avatar);
  }
}

// ──────────────────────────────────────────────────────────
// ✅ SHARED UI: Followers / Following Panel
// ──────────────────────────────────────────────────────────
class _FollowersFollowingPanel extends StatefulWidget {
  final String targetUserId;
  final int initialIndex; 
  final bool isSheet;
  final bool isDark;
  final void Function(SocialUser user) onOpenProfile;

  const _FollowersFollowingPanel({
    required this.targetUserId,
    required this.initialIndex,
    required this.onOpenProfile,
    this.isSheet = false,
    required this.isDark,
  });

  @override
  State<_FollowersFollowingPanel> createState() => _FollowersFollowingPanelState();
}

class _FollowersFollowingPanelState extends State<_FollowersFollowingPanel> {
  late final TextEditingController _search;
  late int _tabIndex;

  bool _loadingFollowers = true;
  bool _loadingFollowing = true;

  List<SocialUser> _followers = [];
  List<SocialUser> _following = [];

  final Map<String, bool> _isFollowingCache = {};
  final Set<String> _loadingStatus = {};
  final Set<String> _toggling = {};

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _tabIndex = widget.initialIndex;
    _loadBoth();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadBoth() async {
    setState(() {
      _loadingFollowers = true;
      _loadingFollowing = true;
    });
    await Future.wait([_loadFollowers(), _loadFollowing()]);
  }

  Future<void> _loadFollowers() async {
    try {
      final list = await r2vSocial.getFollowers(widget.targetUserId);
      if (!mounted) return;
      setState(() => _followers = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _followers = []);
    } finally {
      if (mounted) setState(() => _loadingFollowers = false);
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final list = await r2vSocial.getFollowing(widget.targetUserId);
      if (!mounted) return;
      setState(() => _following = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _following = []);
    } finally {
      if (mounted) setState(() => _loadingFollowing = false);
    }
  }

  Future<void> _ensureFollowStatus(String userId) async {
    if (_isFollowingCache.containsKey(userId) || _loadingStatus.contains(userId)) return;
    _loadingStatus.add(userId);
    try {
      final p = await r2vSocial.getProfile(userId);
      if (!mounted) return;
      setState(() => _isFollowingCache[userId] = p.isFollowing);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFollowingCache[userId] = false);
    } finally {
      _loadingStatus.remove(userId);
    }
  }

  Future<void> _toggleFollow(String userId) async {
    if (_toggling.contains(userId)) return;
    final current = _isFollowingCache[userId] ?? false;
    setState(() => _toggling.add(userId));
    try {
      if (current) await r2vSocial.unfollow(userId);
      else await r2vSocial.follow(userId);
      if (!mounted) return;
      setState(() => _isFollowingCache[userId] = !current);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _toggling.remove(userId));
    }
  }

  List<SocialUser> _filtered(List<SocialUser> list) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((u) => u.username.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isWebWide = MediaQuery.of(context).size.width >= 900;
    final isDark = widget.isDark;

    final followersLoading = _loadingFollowers;
    final followingLoading = _loadingFollowing;

    final followers = _filtered(_followers);
    final following = _filtered(_following);

    final activeList = _tabIndex == 0 ? followers : following;
    final activeLoading = _tabIndex == 0 ? followersLoading : followingLoading;

    final title = _tabIndex == 0 ? "Followers" : "Following";

    final panelWidth = isWebWide ? 460.0 : double.infinity;
    final panelHeight = widget.isSheet
        ? MediaQuery.of(context).size.height * 0.86
        : (isWebWide ? 560.0 : MediaQuery.of(context).size.height * 0.7);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: isDark ? Colors.black.withOpacity(0.60) : Colors.white.withOpacity(0.95),
          child: Container(
            width: panelWidth,
            height: panelHeight,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white),
              boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w800, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _FFTab(label: "Followers", active: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0), isDark: isDark)),
                    const SizedBox(width: 10),
                    Expanded(child: _FFTab(label: "Following", active: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1), isDark: isDark)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: isDark ? Colors.white54 : Colors.black38, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: "Search users…",
                            hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38, fontSize: 13),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_search.text.isNotEmpty)
                        InkWell(
                          onTap: () {
                            _search.clear();
                            setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: activeLoading
                      ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : const Color(0xFFBC70FF)))
                      : activeList.isEmpty
                          ? Center(
                              child: Text(
                                "No ${title.toLowerCase()} yet",
                                style: TextStyle(color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54, fontWeight: FontWeight.w600),
                              ),
                            )
                          : ListView.separated(
                              itemCount: activeList.length,
                              separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05), height: 1),
                              itemBuilder: (context, i) {
                                final u = activeList[i];
                                _ensureFollowStatus(u.userId);

                                final isFollowing = _isFollowingCache[u.userId] ?? false;
                                final isLoadingStatus = _loadingStatus.contains(u.userId);
                                final isToggling = _toggling.contains(u.userId);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                  leading: _FFAvatar(url: u.avatarUrl, isDark: isDark),
                                  title: Text(u.username, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w700)),
                                  onTap: () => widget.onOpenProfile(u),
                                  trailing: SizedBox(
                                    height: 34,
                                    child: isLoadingStatus
                                        ? SizedBox(
                                            width: 34, height: 34,
                                            child: Padding(padding: const EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.white : const Color(0xFFBC70FF))),
                                          )
                                        : OutlinedButton(
                                            onPressed: isToggling ? null : () => _toggleFollow(u.userId),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: isFollowing ? (isDark ? Colors.white : Colors.black87) : Colors.white,
                                              backgroundColor: isFollowing 
                                                  ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)) 
                                                  : const Color(0xFF8A4FFF),
                                              side: BorderSide(color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.05)),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            child: Text(
                                              isToggling ? "..." : (isFollowing ? "Following" : "Follow"),
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                            ),
                                          ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FFTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool isDark;

  const _FFTab({required this.label, required this.active, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: active ? const LinearGradient(colors: [Color(0xFF8A4FFF), Color(0xFFBC70FF)]) : null,
          color: active ? null : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.05)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: active ? Colors.white : (isDark ? Colors.white : const Color(0xFF1E293B)), fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _FFAvatar extends StatelessWidget {
  final String? url;
  final bool isDark;
  const _FFAvatar({this.url, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.startsWith('data:image')) {
      try {
        final parts = url!.split(',');
        final bytes = base64Decode(parts.last);
        return CircleAvatar(backgroundImage: MemoryImage(bytes));
      } catch (_) {}
    }
    if (url != null && url!.isNotEmpty && !url!.startsWith('data:image')) {
      return CircleAvatar(backgroundImage: NetworkImage(url!));
    }
    return CircleAvatar(
      backgroundColor: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05),
      child: Icon(Icons.person, color: isDark ? Colors.white70 : Colors.black26),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool isDark;
  const _TabChip({required this.label, this.active = false, this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: active ? const LinearGradient(colors: [Color(0xFF8A4FFF), Color(0xFFBC70FF)]) : null,
          color: active ? null : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.05)),
        ),
        child: Text(
          label,
          style: TextStyle(color: active ? Colors.white : (isDark ? Colors.white : const Color(0xFF1E293B)), fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

enum ProfileTab { posts, saved, liked }
ProfileTab? _parseProfileTab(String? value) {
  switch (value?.toLowerCase()) {
    case 'posts': return ProfileTab.posts;
    case 'saved': return ProfileTab.saved;
    case 'liked': return ProfileTab.liked;
    default: return null;
  }
}

class _MStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;
  final bool isDark;
  const _MStat({required this.value, required this.label, this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(value, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54, fontSize: 12)),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: content),
    );
  }
}

class _PillTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _PillTag({required this.icon, required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

Future<void> _showAssetPreview(BuildContext context, MarketplaceAsset asset) async {
  final bool isWebWide = MediaQuery.of(context).size.width >= 900;
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  Future<void> startDownload({String? format}) async {
    try {
      final url = await r2vMarketplace.downloadAsset(asset.id, format: format);
      if (url.isEmpty) throw Exception('Missing download url');
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to start download')));
    }
  }

  Widget panel = AssetDetailsPanel(
    asset: asset,
    isDark: isDark,
    onClose: () => Navigator.pop(context),
    onFreeDownload: (_, format) => startDownload(format: format),
    onPaidBuy: (selected) => Navigator.pushNamed(context, '/payment', arguments: selected),
  );

  if (isWebWide) {
    await showDialog(
      context: context,
      barrierColor: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.4),
      builder: (_) => Dialog(backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(16), child: SizedBox(width: 360, child: panel)),
    );
  } else {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(padding: const EdgeInsets.all(12), child: SizedBox(height: MediaQuery.of(context).size.height * 0.72, child: panel)),
    );
  }
}

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
                "R2V",
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
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05), shape: BoxShape.circle),
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

class _EditProfileDialog extends StatefulWidget {
  final String initialName;
  final String initialRole;
  final String initialBio;
  final Uint8List? initialAvatar;
  final Future<void> Function(String name, String role, String bio, Uint8List? avatarBytes) onSave;
  final bool isDark;

  const _EditProfileDialog({
    required this.initialName, required this.initialRole, required this.initialBio,
    required this.initialAvatar, required this.onSave, required this.isDark,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late TextEditingController _nameController;
  late TextEditingController _roleController;
  late TextEditingController _bioController;
  Uint8List? _avatarBytes;
  final ImagePicker _imagePicker = ImagePicker();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _roleController = TextEditingController(text: widget.initialRole);
    _bioController = TextEditingController(text: widget.initialBio);
    _avatarBytes = widget.initialAvatar;
  }

  Future<void> _pickAvatar() async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false, type: FileType.image);
      if (result != null && result.files.single.bytes != null) setState(() => _avatarBytes = result.files.single.bytes);
    } else {
      final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => _avatarBytes = bytes);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose(); _roleController.dispose(); _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = MediaQuery.of(context).size.width >= 900;
    final dialogWidth = isWeb ? 480.0 : MediaQuery.of(context).size.width - 40;
    final isDark = widget.isDark;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.95),
            child: Container(
              width: dialogWidth,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text("Edit Profile", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54, size: 20)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Column(
                      children: [
                        Container(
                          width: 90, height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.05),
                            border: Border.all(color: isDark ? Colors.white.withOpacity(0.22) : Colors.black.withOpacity(0.1), width: 1.2),
                          ),
                          child: ClipOval(
                            child: _avatarBytes != null
                                ? Image.memory(_avatarBytes!, fit: BoxFit.cover)
                                : Icon(Icons.person, size: 40, color: isDark ? Colors.white54 : Colors.black26),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text("Tap to change profile picture", style: TextStyle(color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _fieldLabel("Display Name", isDark), const SizedBox(height: 6),
                  _glassTextField(_nameController, isDark, hint: "Your name"),
                  const SizedBox(height: 12),
                  _fieldLabel("Role / Title", isDark), const SizedBox(height: 6),
                  _glassTextField(_roleController, isDark, hint: "e.g. 3D Artist · Designer"),
                  const SizedBox(height: 12),
                  _fieldLabel("Bio", isDark), const SizedBox(height: 6),
                  _glassTextField(_bioController, isDark, hint: "Tell others about your work…", maxLines: 3),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                await widget.onSave(
                                  _nameController.text.trim().isEmpty ? widget.initialName : _nameController.text.trim(),
                                  _roleController.text.trim().isEmpty ? widget.initialRole : _roleController.text.trim(),
                                  _bioController.text.trim().isEmpty ? widget.initialBio : _bioController.text.trim(),
                                  _avatarBytes,
                                );
                                if (mounted) setState(() => _saving = false);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8A4FFF), foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0,
                        ),
                        child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Save", style: TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _fieldLabel(String text, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1E293B), fontSize: 12.5, fontWeight: FontWeight.w500)),
    );
  }

  Widget _glassTextField(TextEditingController controller, bool isDark, {String? hint, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38, fontSize: 12.5),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

// ==========================================
// BACKGROUND LAYERS
// ==========================================

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
  Widget build(BuildContext context) => RepaintBoundary(child: _MeshyBgCore(isDark: isDark));
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

    _ps = List.generate(target, (_) {
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
  bool shouldRepaint(covariant _MeshPainter old) {
    return old.time != time ||
        old.size != size ||
        old.mouse != mouse ||
        old.hasMouse != hasMouse ||
        old.particles.length != particles.length;
  }
}
