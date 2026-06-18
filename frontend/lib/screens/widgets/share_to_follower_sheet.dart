import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../api/chat_service.dart';
import '../../api/marketplace_service.dart';
import '../../api/r2v_api.dart';

/// Opens the "Send to Follower" sheet for a marketplace asset.
///
/// Lists the people the current user is actually allowed to message (the
/// backend `GET /chat/users` returns mutual-followers only), lets them pick one
/// or more, and sends the asset's public link as a chat message via the
/// existing chat endpoints. Returns the number of followers the asset was sent
/// to (0 if cancelled / nothing sent).
Future<int?> showShareToFollowerSheet(
  BuildContext context, {
  required String assetId,
  required String assetTitle,
  required bool isDark,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareToFollowerSheet(
      assetId: assetId,
      assetTitle: assetTitle,
      isDark: isDark,
    ),
  );
}

class _ShareToFollowerSheet extends StatefulWidget {
  final String assetId;
  final String assetTitle;
  final bool isDark;

  const _ShareToFollowerSheet({
    required this.assetId,
    required this.assetTitle,
    required this.isDark,
  });

  @override
  State<_ShareToFollowerSheet> createState() => _ShareToFollowerSheetState();
}

class _ShareToFollowerSheetState extends State<_ShareToFollowerSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<ChatUser> _users = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _sending = false;
  bool _needsLogin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({String search = ''}) async {
    setState(() {
      _loading = true;
      _error = null;
      _needsLogin = false;
    });
    try {
      final users = await r2vChat.searchUsers(search: search);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 401/403 → the viewer isn't authenticated; prompt a login instead of
        // showing a raw error.
        if (e.statusCode == 401 || e.statusCode == 403) {
          _needsLogin = true;
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your followers. Please try again.';
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _load(search: value.trim());
    });
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);

    // Public, shareable link — never a presigned/GLB URL.
    final url = MarketplaceService.shareUrlFor(widget.assetId);
    final title =
        widget.assetTitle.trim().isEmpty ? 'a 3D model' : widget.assetTitle.trim();
    final body = 'Check out this 3D model on R2V: $title\n$url';

    var sent = 0;
    final failures = <String>[];
    for (final userId in _selected) {
      try {
        final conv = await r2vChat.startConversation([userId]);
        await r2vChat.send(conv.id, body);
        sent++;
      } on ApiException catch (e) {
        failures.add(e.message);
      } catch (_) {
        failures.add('Failed to send to a follower');
      }
    }

    if (!mounted) return;
    if (sent > 0) {
      Navigator.of(context).pop(sent);
    } else {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failures.isNotEmpty ? failures.first : 'Could not send the message.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final media = MediaQuery.of(context);
    // Responsive: cap the sheet height and lift it above the keyboard.
    final maxHeight = media.size.height * 0.82;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF120B26).withOpacity(0.96)
                    : Colors.white.withOpacity(0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.10)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _grabber(isDark),
                    _header(isDark),
                    if (!_needsLogin) _searchField(isDark),
                    Flexible(child: _body(isDark)),
                    if (!_needsLogin) _footer(isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber(bool isDark) => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: isDark ? Colors.white24 : Colors.black12,
          borderRadius: BorderRadius.circular(99),
        ),
      );

  Widget _header(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 12, 8),
      child: Row(
        children: [
          Icon(Icons.send_rounded,
              size: 18, color: isDark ? Colors.white : const Color(0xFF1E293B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Share With Friends',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1E293B),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(0),
            icon: Icon(Icons.close_rounded,
                color: isDark ? Colors.white60 : Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _searchField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _search,
        onChanged: _onSearchChanged,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Search followers',
          hintStyle:
              TextStyle(color: isDark ? Colors.white38 : Colors.black38),
          prefixIcon: Icon(Icons.search_rounded,
              color: isDark ? Colors.white38 : Colors.black38),
          filled: true,
          fillColor: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_needsLogin) {
      return _centered(
        isDark,
        icon: Icons.lock_outline_rounded,
        title: 'Sign in to share with followers',
        subtitle: 'You need to be logged in to message your followers.',
        action: TextButton(
          onPressed: () {
            Navigator.of(context).pop(0);
            Navigator.of(context).pushNamed('/signin');
          },
          child: const Text('Go to sign in'),
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _centered(
        isDark,
        icon: Icons.error_outline_rounded,
        title: 'Something went wrong',
        subtitle: _error!,
        action: TextButton(
          onPressed: () => _load(search: _search.text.trim()),
          child: const Text('Retry'),
        ),
      );
    }
    if (_users.isEmpty) {
      return _centered(
        isDark,
        icon: Icons.group_outlined,
        title: 'No followers you can message yet',
        subtitle:
            'You can only share with people who follow you back. Once you have mutual followers, they’ll appear here.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _users.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 68,
        color: isDark ? Colors.white10 : Colors.black12,
      ),
      itemBuilder: (_, i) => _userTile(_users[i], isDark),
    );
  }

  Widget _userTile(ChatUser u, bool isDark) {
    final selected = _selected.contains(u.id);
    return InkWell(
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(u.id);
        } else {
          _selected.add(u.id);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              backgroundImage:
                  (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                      ? NetworkImage(u.avatarUrl!)
                      : null,
              child: (u.avatarUrl == null || u.avatarUrl!.isEmpty)
                  ? Text(
                      u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                u.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? const Color(0xFF8A4FFF) : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF8A4FFF)
                      : (isDark ? Colors.white38 : Colors.black26),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(bool isDark) {
    final count = _selected.length;
    final enabled = count > 0 && !_sending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: enabled ? _send : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8A4FFF),
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                isDark ? Colors.white12 : Colors.black12,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  count == 0
                      ? 'Select followers'
                      : 'Send to $count follower${count == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ),
    );
  }

  Widget _centered(
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: isDark ? Colors.white38 : Colors.black26),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }
}
