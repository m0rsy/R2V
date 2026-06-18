import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_exception.dart';
import '../api/chat_service.dart';
import '../api/marketplace_service.dart';
import '../api/r2v_api.dart';
import '../api/recording_bytes.dart';

/// Shared R2V chat palette (kept on the product's dark violet theme).
class _Palette {
  static const bg = Color(0xFF0B0712);
  static const panel = Color(0xFF161021);
  static const panelAlt = Color(0xFF0F0A1A);
  // Premium glass wash used behind search bars / message composer instead of a
  // heavy dark filled box.
  static const inputGlass = Color(0x0DFFFFFF); // white @ 0.05
  static const violet = Color(0xFF8A4FFF);
  static const border = Color(0x1AFFFFFF);
  static const mineBubble = Color(0xFF6D28D9);
  static const theirsBubble = Color(0xFF1E1730);
  static const unread = Color(0xFFF72585);
}

// --------------------------------------------------------------------------- //
// Time helpers (no intl dependency in this project).
// --------------------------------------------------------------------------- //

DateTime? _parseTs(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try {
    return DateTime.parse(iso).toLocal();
  } catch (_) {
    return null;
  }
}

String _clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $ampm';
}

/// WhatsApp-style preview time for the conversation list.
String _listTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return _clockTime(t);
  if (diff == 1) return 'Yesterday';
  if (diff < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[t.weekday - 1];
  }
  final dd = t.day.toString().padLeft(2, '0');
  final mm = t.month.toString().padLeft(2, '0');
  final yy = (t.year % 100).toString().padLeft(2, '0');
  return '$dd/$mm/$yy';
}

/// Date-separator label shown between groups of messages.
String _dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[t.month - 1]} ${t.day}, ${t.year}';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.initialUserId});

  /// When provided, a conversation with this user is opened on launch.
  final String? initialUserId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String _myId = '';
  bool _loading = true;
  String? _error;
  List<ChatConversation> _conversations = [];
  ChatConversation? _selected;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await r2vAuth.me();
      _myId = (me['id'] ?? '').toString();
      await _loadConversations();
      if (widget.initialUserId != null && widget.initialUserId!.isNotEmpty) {
        await _openWithUser(widget.initialUserId!);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load chat';
        _loading = false;
      });
    }
  }

  Future<void> _loadConversations() async {
    final convs = await r2vChat.conversations();
    if (!mounted) return;
    setState(() {
      _conversations = convs;
      if (_selected != null) {
        _selected = convs.firstWhere(
          (c) => c.id == _selected!.id,
          orElse: () => _selected!,
        );
      }
    });
  }

  Future<void> _openWithUser(String userId) async {
    try {
      final conv = await r2vChat.startConversation([userId]);
      await _loadConversations();
      if (!mounted) return;
      setState(() => _selected = conv);
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e is ApiException ? e.message : 'Something went wrong'),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _newChat() async {
    final user = await showModalBottomSheet<ChatUser>(
      context: context,
      backgroundColor: _Palette.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _UserSearchSheet(),
    );
    if (user == null) return;
    await _openWithUser(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: _Palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Messages',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'New message',
            onPressed: _loading ? null : _newChat,
            icon: const Icon(Icons.edit_square, color: _Palette.violet),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const _ListSkeleton()
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _bootstrap)
                : isWide
                    ? _buildWide()
                    : _buildNarrow(),
      ),
    );
  }

  Widget _buildWide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: _ConversationList(
            conversations: _conversations,
            myId: _myId,
            selectedId: _selected?.id,
            onTap: (c) => setState(() => _selected = c),
            onNew: _newChat,
            onRefresh: _loadConversations,
          ),
        ),
        const VerticalDivider(width: 1, color: _Palette.border),
        Expanded(
          child: _selected == null
              ? const _EmptyDetail()
              : _ConversationPane(
                  key: ValueKey(_selected!.id),
                  conversation: _selected!,
                  myId: _myId,
                  onChanged: _loadConversations,
                ),
        ),
      ],
    );
  }

  Widget _buildNarrow() {
    if (_selected != null) {
      return _ConversationPane(
        key: ValueKey(_selected!.id),
        conversation: _selected!,
        myId: _myId,
        onBack: () => setState(() => _selected = null),
        onChanged: _loadConversations,
      );
    }
    return _ConversationList(
      conversations: _conversations,
      myId: _myId,
      selectedId: null,
      onTap: (c) => setState(() => _selected = c),
      onNew: _newChat,
      onRefresh: _loadConversations,
    );
  }
}

// --------------------------------------------------------------------------- //
// Conversation list (with WhatsApp-style search + previews)
// --------------------------------------------------------------------------- //

class _ConversationList extends StatefulWidget {
  const _ConversationList({
    required this.conversations,
    required this.myId,
    required this.selectedId,
    required this.onTap,
    required this.onNew,
    required this.onRefresh,
  });

  final List<ChatConversation> conversations;
  final String myId;
  final String? selectedId;
  final ValueChanged<ChatConversation> onTap;
  final VoidCallback onNew;
  final Future<void> Function() onRefresh;

  @override
  State<_ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<_ConversationList> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChatConversation> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.conversations;
    return widget.conversations.where((c) {
      final other = c.otherParticipant(widget.myId);
      final name = (c.title ?? other?.username ?? '').toLowerCase();
      final preview = (c.lastMessage?.body ?? '').toLowerCase();
      return name.contains(q) || preview.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Palette.panel,
      child: Column(
        children: [
          _searchBar(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search chats',
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: _Palette.inputGlass,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: _Palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: _Palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: _Palette.violet, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (widget.conversations.isEmpty) {
      return _EmptyConversations(onNew: widget.onNew);
    }
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Text('No chats match your search',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return RefreshIndicator(
      color: _Palette.violet,
      backgroundColor: _Palette.panel,
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: items.length,
        itemBuilder: (context, i) => _ConversationTile(
          conversation: items[i],
          myId: widget.myId,
          selected: items[i].id == widget.selectedId,
          onTap: () => widget.onTap(items[i]),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.myId,
    required this.selected,
    required this.onTap,
  });

  final ChatConversation conversation;
  final String myId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final other = c.otherParticipant(myId);
    final title = c.title ?? other?.username ?? 'Conversation';
    final lastMsg = c.lastMessage;
    final preview = lastMsg == null
        ? 'No messages yet'
        : '${lastMsg.isMine ? 'You: ' : ''}${lastMsg.body}';
    final ts = _parseTs(c.lastMessageAt ?? lastMsg?.createdAt);
    final unread = c.unreadCount;

    return Material(
      color: selected
          ? _Palette.violet.withOpacity(0.14)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _Avatar(url: other?.avatarUrl, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: unread > 0 ? Colors.white70 : Colors.white54,
                            fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    ts != null ? _listTime(ts) : '',
                    style: TextStyle(
                      color: unread > 0 ? _Palette.violet : Colors.white38,
                      fontSize: 11,
                      fontWeight:
                          unread > 0 ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (unread > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: _Palette.unread,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text('${unread > 99 ? '99+' : unread}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    )
                  else
                    const SizedBox(height: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Conversation message pane
// --------------------------------------------------------------------------- //

class _ConversationPane extends StatefulWidget {
  const _ConversationPane({
    super.key,
    required this.conversation,
    required this.myId,
    this.onBack,
    this.onChanged,
  });

  final ChatConversation conversation;
  final String myId;
  final VoidCallback? onBack;
  final VoidCallback? onChanged;

  @override
  State<_ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<_ConversationPane> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // TODO(realtime): swap polling for a WebSocket stream when the backend
    // exposes one. Polling keeps the receiver in sync without refreshing.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await r2vChat.messages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = detail.messages;
        _loading = false;
      });
      _jumpToBottom();
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final detail = await r2vChat.messages(widget.conversation.id);
      if (!mounted) return;
      final wasAtBottom = !_scroll.hasClients ||
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 60;
      // Avoid a needless rebuild/flicker when nothing changed.
      if (detail.messages.length != _messages.length ||
          (detail.messages.isNotEmpty &&
              _messages.isNotEmpty &&
              detail.messages.last.id != _messages.last.id)) {
        setState(() => _messages = detail.messages);
        if (wasAtBottom) _jumpToBottom();
        widget.onChanged?.call();
      }
    } catch (_) {
      // silent during polling
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final detail = await r2vChat.send(widget.conversation.id, text);
      _input.clear();
      if (!mounted) return;
      // Dedupe in case a poll already pulled the new message in.
      final existing = _messages.map((m) => m.id).toSet();
      final added = detail.messages.where((m) => !existing.contains(m.id));
      setState(() {
        _messages = [..._messages, ...added];
        _sending = false;
      });
      _jumpToBottom();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Failed to send'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyDetail(ConversationDetail detail) {
    final existing = _messages.map((m) => m.id).toSet();
    final added = detail.messages.where((m) => !existing.contains(m.id));
    setState(() => _messages = [..._messages, ...added]);
    _jumpToBottom();
    widget.onChanged?.call();
  }

  Future<void> _sendAttachment(
    Uint8List bytes,
    String name,
    String? mime,
    String kind,
    String? text,
  ) async {
    final detail = await r2vChat.sendAttachment(
      widget.conversation.id,
      bytes: bytes,
      fileName: name,
      contentType: mime,
      text: text,
      kind: kind,
    );
    if (!mounted) return;
    _applyDetail(detail);
  }

  Future<void> _sendVoice(
    Uint8List bytes,
    String name,
    String? mime,
    int durationSeconds,
  ) async {
    final detail = await r2vChat.sendVoiceNote(
      widget.conversation.id,
      bytes: bytes,
      fileName: name,
      contentType: mime,
      durationSeconds: durationSeconds,
    );
    if (!mounted) return;
    _applyDetail(detail);
  }

  @override
  Widget build(BuildContext context) {
    final other = widget.conversation.otherParticipant(widget.myId);
    final title = widget.conversation.title ?? other?.username ?? 'Conversation';

    return Container(
      color: _Palette.bg,
      child: Column(
        children: [
          _header(other, title),
          Expanded(child: _messageArea()),
          _Composer(
            controller: _input,
            sending: _sending,
            onSendText: _send,
            onSendAttachment: _sendAttachment,
            onSendVoice: _sendVoice,
          ),
        ],
      ),
    );
  }

  Widget _header(ChatUser? other, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        color: _Palette.panel,
        border: Border(bottom: BorderSide(color: _Palette.border)),
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            )
          else
            const SizedBox(width: 8),
          _Avatar(url: other?.avatarUrl, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                if (other != null)
                  Text(other.role,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageArea() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _Palette.violet));
    }
    if (_messages.isEmpty) {
      return const _EmptyMessages();
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final showDay = _shouldShowDay(prev, m);
        final ts = _parseTs(m.createdAt);
        return Column(
          children: [
            if (showDay && ts != null) _DayChip(label: _dayLabel(ts)),
            _MessageBubble(message: m, time: ts),
          ],
        );
      },
    );
  }

  bool _shouldShowDay(ChatMessage? prev, ChatMessage current) {
    final cur = _parseTs(current.createdAt);
    if (cur == null) return false;
    if (prev == null) return true;
    final p = _parseTs(prev.createdAt);
    if (p == null) return true;
    return p.year != cur.year || p.month != cur.month || p.day != cur.day;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.time});
  final ChatMessage message;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final maxW = MediaQuery.of(context).size.width * 0.72 > 460
        ? 460.0
        : MediaQuery.of(context).size.width * 0.72;

    // Marketplace asset share: when the body carries a public asset deep link
    // (and there are no file attachments), render a rich, Instagram-style asset
    // card instead of the raw link text. Falls back to plain text otherwise.
    final sharedAssetId =
        message.attachments.isEmpty ? _sharedAssetId(message.body) : null;
    if (sharedAssetId != null) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(maxWidth: maxW),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AssetShareCard(assetId: sharedAssetId, mine: mine),
              if (time != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                  child: Text(
                    _clockTime(time!),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 10.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
        constraints: BoxConstraints(maxWidth: maxW),
        decoration: BoxDecoration(
          color: mine ? _Palette.mineBubble : _Palette.theirsBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 3),
            bottomRight: Radius.circular(mine ? 3 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final att in message.attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _AttachmentView(attachment: att, mine: mine),
              ),
            if (message.body.isNotEmpty)
              Text(
                message.body,
                style: TextStyle(
                  color: mine ? Colors.white : Colors.white.withOpacity(0.92),
                  fontSize: 14.5,
                  height: 1.35,
                ),
              ),
            if (time != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  _clockTime(time!),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 10.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Matches the public marketplace deep link embedded in a shared message body,
// e.g. "https://realtwovirtual.com/#/explore?asset=<uuid>". Only our share
// feature (or a user pasting the same public link) produces this, so it is a
// safe signal to render the rich asset card.
final RegExp _assetShareLinkRe = RegExp(r'explore\?asset=([A-Za-z0-9\-]+)');

String? _sharedAssetId(String body) {
  final m = _assetShareLinkRe.firstMatch(body);
  final id = m?.group(1);
  return (id != null && id.isNotEmpty) ? id : null;
}

// Process-lifetime cache of share-card asset fetches, keyed by asset id, so the
// frequently-rebuilt message list doesn't refetch on every frame. Failed
// futures are evicted on retry (see _AssetShareCard).
final Map<String, Future<MarketplaceAsset>> _assetShareCache = {};

Future<MarketplaceAsset> _cachedAsset(String id) =>
    _assetShareCache.putIfAbsent(id, () => r2vMarketplace.getAsset(id));

/// Instagram-style rich card for a shared marketplace asset inside a chat
/// bubble. Fetches fresh asset data by id (so the thumbnail is a fresh,
/// short-lived presigned image — never a stored/expired URL, never the GLB).
class _AssetShareCard extends StatefulWidget {
  const _AssetShareCard({required this.assetId, required this.mine});
  final String assetId;
  final bool mine;

  @override
  State<_AssetShareCard> createState() => _AssetShareCardState();
}

class _AssetShareCardState extends State<_AssetShareCard> {
  late Future<MarketplaceAsset> _future;

  @override
  void initState() {
    super.initState();
    _future = _cachedAsset(widget.assetId);
  }

  void _retry() {
    setState(() {
      _assetShareCache.remove(widget.assetId);
      _future = _cachedAsset(widget.assetId);
    });
  }

  void _openAsset() {
    Navigator.of(context).pushNamed('/explore?asset=${widget.assetId}');
  }

  String _priceLabel(MarketplaceAsset a) =>
      (!a.isPaid || a.price <= 0) ? 'FREE' : 'EGP ${a.price}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MarketplaceAsset>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _shell(child: _loading());
        }
        if (snap.hasError || !snap.hasData) {
          return _shell(child: _unavailable());
        }
        return _shell(child: _content(snap.data!), onTap: _openAsset);
      },
    );
  }

  // Dark glass card frame with subtle border + glow.
  Widget _shell({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            color: const Color(0xFF160E2B).withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF8A4FFF).withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8A4FFF).withOpacity(0.22),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  Widget _loading() => const SizedBox(
        height: 210,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );

  Widget _unavailable() => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 26),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Asset unavailable',
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: _retry,
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _content(MarketplaceAsset a) {
    final chips = <Widget>[
      _chip(_priceLabel(a),
          highlight: (!a.isPaid || a.price <= 0)),
      if (a.category.isNotEmpty) _chip(a.category),
      if (a.style.isNotEmpty) _chip(a.style),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _thumbnail(a),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                a.title.isNotEmpty ? a.title : 'Untitled model',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'by ${a.author}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
              if (a.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  a.description.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openAsset,
                  icon: const Icon(Icons.view_in_ar_rounded, size: 18),
                  label: const Text('View Model'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A4FFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumbnail(MarketplaceAsset a) {
    final url = a.thumbUrl;
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        color: Colors.black.withOpacity(0.35),
        width: double.infinity,
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _thumbPlaceholder(),
                errorBuilder: (context, _, __) => _thumbPlaceholder(),
              )
            : _thumbPlaceholder(),
      ),
    );
  }

  Widget _thumbPlaceholder() => Center(
        child: Icon(
          Icons.view_in_ar_rounded,
          size: 40,
          color: const Color(0xFF8A4FFF).withOpacity(0.7),
        ),
      );

  Widget _chip(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF22C55E).withOpacity(0.18)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: highlight
              ? const Color(0xFF22C55E).withOpacity(0.55)
              : Colors.white.withOpacity(0.12),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlight ? const Color(0xFF6EE7A8) : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _humanSize(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

String _fmtDuration(int seconds) {
  final m = (seconds ~/ 60).toString();
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

Future<void> _openUrl(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open file')),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  const _AttachmentView({required this.attachment, required this.mine});
  final ChatAttachment attachment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final att = attachment;
    if (att.isVoice) {
      return _AudioMessage(attachment: att, mine: mine);
    }
    if (att.isImage && att.url != null) {
      return GestureDetector(
        onTap: () => _openUrl(context, att.url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            att.url!,
            width: 220,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, p) => p == null
                ? child
                : Container(
                    width: 220,
                    height: 140,
                    color: Colors.black26,
                    child: const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _Palette.violet)),
                  ),
            errorBuilder: (c, e, s) => _fileChip(context),
          ),
        ),
      );
    }
    return _fileChip(context);
  }

  Widget _fileChip(BuildContext context) {
    IconData icon = Icons.insert_drive_file_outlined;
    final type = attachment.attachmentType;
    if (type == 'model') icon = Icons.view_in_ar_outlined;
    if (type == 'document') icon = Icons.description_outlined;
    return InkWell(
      onTap: () => _openUrl(context, attachment.url),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text(
                    _humanSize(attachment.fileSize),
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.download_rounded, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AudioMessage extends StatefulWidget {
  const _AudioMessage({required this.attachment, required this.mine});
  final ChatAttachment attachment;
  final bool mine;

  @override
  State<_AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<_AudioMessage> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    final d = widget.attachment.durationSeconds;
    if (d != null) _total = Duration(seconds: d);
    _subs = [
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted && d > Duration.zero) setState(() => _total = d);
      }),
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.attachment.url;
    if (url == null) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play(UrlSource(url));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice note')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total.inMilliseconds == 0 ? 1 : _total.inMilliseconds;
    final progress = (_position.inMilliseconds / total).clamp(0.0, 1.0);
    final shown = _playing || _position > Duration.zero ? _position : _total;
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.mic, color: Colors.white70, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    _fmtDuration(shown.inSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: _Palette.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
    );
  }
}

// --------------------------------------------------------------------------- //
// Composer
// --------------------------------------------------------------------------- //

class _PendingAttachment {
  _PendingAttachment({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.kind,
  });
  final Uint8List bytes;
  final String name;
  final String? mime;
  final String kind; // image | document | model | other

  bool get isImage => kind == 'image';
  int get size => bytes.length;
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSendText,
    required this.onSendAttachment,
    required this.onSendVoice,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSendText;
  final Future<void> Function(
    Uint8List bytes,
    String name,
    String? mime,
    String kind,
    String? text,
  ) onSendAttachment;
  final Future<void> Function(
    Uint8List bytes,
    String name,
    String? mime,
    int durationSeconds,
  ) onSendVoice;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _recorder = AudioRecorder();
  _PendingAttachment? _pending;
  bool _busy = false;

  // recording state
  bool _recording = false;
  int _elapsed = 0;
  Timer? _recordTimer;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _kindFromExtension(String name, String? mime) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const images = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
    const models = {'glb', 'gltf', 'obj', 'fbx', 'stl'};
    const docs = {'pdf', 'doc', 'docx', 'txt', 'zip'};
    if ((mime ?? '').startsWith('image/') || images.contains(ext)) return 'image';
    if (models.contains(ext)) return 'model';
    if (docs.contains(ext)) return 'document';
    return 'other';
  }

  Future<void> _pickFile() async {
    if (_busy || _recording) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'png', 'jpg', 'jpeg', 'webp', 'gif',
          'pdf', 'doc', 'docx', 'txt', 'zip',
          'glb', 'gltf', 'obj', 'fbx', 'stl',
        ],
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
      setState(() {
        _pending = _PendingAttachment(
          bytes: bytes,
          name: f.name,
          mime: null,
          kind: _kindFromExtension(f.name, null),
        );
      });
    } catch (e) {
      _toast('File pick failed');
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = widget.controller.text.trim();
    final pending = _pending;
    if (pending == null) {
      if (text.isEmpty) return;
      widget.onSendText();
      return;
    }
    // attachment (optionally with text)
    setState(() => _busy = true);
    try {
      await widget.onSendAttachment(
        pending.bytes,
        pending.name,
        pending.mime,
        pending.kind,
        text.isEmpty ? null : text,
      );
      widget.controller.clear();
      if (mounted) setState(() => _pending = null);
    } catch (e) {
      _toast(e is ApiException ? e.message : 'Failed to send attachment');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRecording() async {
    if (_busy || _recording) return;
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
        if (_elapsed >= 300) _stopAndSend(); // 5 min cap
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

  Future<void> _stopAndSend() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    final duration = _elapsed;
    setState(() {
      _recording = false;
      _busy = true;
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
      final mime = kIsWeb ? 'audio/webm' : 'audio/mp4';
      final name = kIsWeb ? 'voice_note.webm' : 'voice_note.m4a';
      await widget.onSendVoice(bytes, name, mime, duration);
    } catch (e) {
      _toast(e is ApiException ? e.message : 'Failed to send voice note');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || widget.sending;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: const BoxDecoration(
        color: _Palette.panel,
        border: Border(top: BorderSide(color: _Palette.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pending != null) _attachmentPreview(),
          _recording ? _recordingBar() : _inputRow(busy),
        ],
      ),
    );
  }

  Widget _attachmentPreview() {
    final p = _pending!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _Palette.panelAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (p.isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(p.bytes,
                  width: 44, height: 44, fit: BoxFit.cover),
            )
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _Palette.violet.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.insert_drive_file_outlined,
                  color: _Palette.violet),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(_humanSize(p.size),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: busyOrRecording ? null : () => setState(() => _pending = null),
            icon: const Icon(Icons.close, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  bool get busyOrRecording => _busy || _recording;

  Widget _recordingBar() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancel',
          onPressed: _cancelRecording,
          icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
        ),
        const _RecordingDot(),
        const SizedBox(width: 8),
        Text(_fmtDuration(_elapsed),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        const Spacer(),
        const Text('Recording…',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(width: 8),
        Material(
          color: _Palette.violet,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _stopAndSend,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputRow(bool busy) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final showSend = hasText || _pending != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Attach file',
          onPressed: busy ? null : _pickFile,
          icon: const Icon(Icons.attach_file, color: Colors.white70),
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            minLines: 1,
            maxLines: 5,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.send,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Type a message…',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: _Palette.inputGlass,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: _Palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: _Palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: _Palette.violet, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: _Palette.violet,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: busy ? null : (showSend ? _send : _startRecording),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(showSend ? Icons.send_rounded : Icons.mic,
                      color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Reusable bits + states
// --------------------------------------------------------------------------- //

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, this.radius = 22});
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: _Palette.violet.withOpacity(0.18),
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      child: hasUrl
          ? null
          : Icon(Icons.person, color: _Palette.violet, size: radius),
    );
  }
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, color: Colors.white38, size: 46),
            const SizedBox(height: 14),
            const Text('No conversations yet',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Start a new chat to message anyone on R2V.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _Palette.violet),
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New message'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.waving_hand_outlined, color: Colors.white24, size: 44),
          SizedBox(height: 12),
          Text('No messages yet',
              style: TextStyle(color: Colors.white70, fontSize: 15)),
          SizedBox(height: 6),
          Text('Say hello 👋',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Palette.bg,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                color: Colors.white24, size: 54),
            SizedBox(height: 14),
            Text('Select a chat to start messaging',
                style: TextStyle(color: Colors.white54, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 8,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
                radius: 26, backgroundColor: Colors.white.withOpacity(0.06)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 220,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 46),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// User search sheet (start a new conversation)
// --------------------------------------------------------------------------- //

class _UserSearchSheet extends StatefulWidget {
  const _UserSearchSheet();

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final _search = TextEditingController();
  List<ChatUser> _users = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _query(value));
  }

  Future<void> _query(String value) async {
    setState(() => _loading = true);
    try {
      final users = await r2vChat.searchUsers(search: value);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('New message',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search people…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  filled: true,
                  fillColor: _Palette.inputGlass,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _Palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _Palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: _Palette.violet, width: 1.4),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: _Palette.violet))
                  : _users.isEmpty
                      ? const Center(
                          child: Text('No users found',
                              style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          itemCount: _users.length,
                          itemBuilder: (context, i) {
                            final u = _users[i];
                            return ListTile(
                              onTap: () => Navigator.of(context).pop(u),
                              leading:
                                  _Avatar(url: u.avatarUrl, radius: 22),
                              title: Text(u.username,
                                  style:
                                      const TextStyle(color: Colors.white)),
                              subtitle: Text(u.role,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
