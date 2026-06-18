import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/ai_jobs_service.dart';
import '../api/ai_chat_service.dart';
import '../api/marketplace_service.dart';
import '../api/r2v_api.dart';
import '../api/api_exception.dart';
import '../utils/web_model_viewer_capture.dart';
import '../widgets/ai_generation_progress_card.dart';
import 'widgets/r2v_section_nav.dart';
import 'widgets/r2v_top_nav_tabs.dart';
import 'widgets/r2v_notification_bell.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  PlatformFile? uploadedImage;
  PlatformFile? uploadedAudio;

  bool _isSidebarCollapsed = false;

  final int _activeIndex = 1;

  final TextEditingController _chatSearchController = TextEditingController();
  String _chatSearch = "";

  // Per-instance (NOT static) so AI chat history can never bleed between users:
  // each logged-in session loads its own conversations from the backend.
  final List<_Conversation> _conversations = [
    _Conversation(id: "c1", title: "New chat"),
  ];
  String _activeConversationId = "c1";
  // Best-effort persistence: when the backend is unreachable we silently fall
  // back to in-memory-only chats (the pre-persistence behaviour).
  bool _backendChatAvailable = true;

  _Conversation get _activeConversation => _conversations.firstWhere(
        (c) => c.id == _activeConversationId,
        orElse: () => _conversations.first,
      );

  List<_Conversation> get _filteredConversations {
    final q = _chatSearch.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations
        .where((c) => c.title.toLowerCase().contains(q))
        .toList();
  }

  // Real logged-in user's display name for the sidebar footer. Defaults to a
  // neutral label until /me resolves; never shows a fabricated identity.
  String _userName = "R2V User";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    _loadCurrentUser();
    _loadConversationsFromBackend();
  }

  // ---------------------------------------------------------------------------
  // AI chat persistence (backed by /ai/chats, scoped to the logged-in user).
  // Every call is best-effort: any failure leaves the in-memory chat working so
  // the AI page never breaks when the backend is briefly unavailable.
  // ---------------------------------------------------------------------------

  /// Loads this user's saved conversations after login. Replaces the default
  /// local "New chat" only when the backend actually returns history.
  Future<void> _loadConversationsFromBackend() async {
    try {
      final chats = await r2vAiChat.listChats();
      if (!mounted || chats.isEmpty) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(chats.map((c) => _Conversation(
                id: c.id,
                title: (c.title == null || c.title!.trim().isEmpty)
                    ? "New chat"
                    : c.title!,
                serverId: c.id,
              )));
        _activeConversationId = _conversations.first.id;
      });
      await _loadMessagesFor(_conversations.first);
    } catch (_) {
      // No backend history available -> keep the local-only experience.
      _backendChatAvailable = false;
    }
  }

  /// Lazily fetches a conversation's messages the first time it is opened.
  Future<void> _loadMessagesFor(_Conversation conv) async {
    if (conv.serverId == null || conv.messagesLoaded) return;
    try {
      final msgs = await r2vAiChat.getMessages(conv.serverId!);
      if (!mounted) return;
      setState(() {
        conv.messages
          ..clear()
          ..addAll(msgs.map(_restoreMessage));
        conv.messagesLoaded = true;
      });
      _scrollToBottom();
      // Re-presign expired media (model preview + uploaded image) from the
      // owned job, so reopening the app restores what the user last saw.
      _refreshRestoredMedia(conv);
    } catch (_) {
      // Leave whatever is already in memory.
    }
  }

  /// Rebuilds a chat bubble from a persisted backend message.
  _ChatMessage _restoreMessage(AiChatMessageDto m) {
    final isUser = m.role == 'user';
    final modelUrl = (m.modelUrl != null && m.modelUrl!.isNotEmpty) ? m.modelUrl : null;
    final jobId = (m.jobId != null && m.jobId!.isNotEmpty) ? m.jobId : null;
    final cm = _ChatMessage(m.text ?? '', null, isUser, modelUrl: modelUrl);
    cm
      ..isGenerating = false
      ..jobStatus = "succeeded"
      ..jobId = jobId
      // Assistant messages tied to a job get their media re-presigned on open;
      // show a loader instead of a stale (likely expired) preview src.
      ..previewRefreshing = !isUser && jobId != null;
    final meta = m.meta;
    if (meta['textured'] is bool) cm.textured = meta['textured'] as bool;
    if (meta['with_texture'] is bool) cm.withTexture = meta['with_texture'] as bool;
    return cm;
  }

  /// Re-presigns model previews and restores uploaded images for a freshly
  /// loaded conversation. Driven by each assistant message's owned [jobId], so
  /// it works even after the originally stored presigned URLs have expired.
  Future<void> _refreshRestoredMedia(_Conversation conv) async {
    // Snapshot the ordered list so index math is stable across awaits.
    final msgs = List<_ChatMessage>.from(conv.messages);
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.isUser || !m.previewRefreshing) continue;
      final jobId = m.jobId;
      if (jobId == null || jobId.isEmpty) {
        if (mounted) setState(() => m.previewRefreshing = false);
        continue;
      }
      try {
        final job = await r2vAiJobs.getJob(jobId);
        if (!mounted) return;
        setState(() {
          final fresh = job.bestModelUrl;
          if (fresh != null && fresh.isNotEmpty) {
            m.modelUrl = fresh; // fresh presigned URL replaces the expired one
            m.previewUnavailable = false;
          } else {
            // No model came back; only flag unavailable if we have nothing.
            m.previewUnavailable = (m.modelUrl == null || m.modelUrl!.isEmpty);
          }
          m.previewRefreshing = false;
          // Restore the uploaded input image onto the nearest preceding user
          // bubble (the "[Image uploaded]" turn) using the re-presigned key.
          final img = job.outputImageUrl;
          if (img != null && img.isNotEmpty) {
            for (var k = i - 1; k >= 0; k--) {
              final prev = msgs[k];
              if (!prev.isUser) continue;
              final hasBytes = prev.image?.bytes?.isNotEmpty ?? false;
              final hasUrl = prev.imageUrl?.isNotEmpty ?? false;
              if (!hasBytes && !hasUrl) prev.imageUrl = img;
              break; // only the immediately preceding user message
            }
          }
        });
      } catch (_) {
        if (!mounted) return;
        // Best-effort: keep any existing (stale) URL as a fallback so we never
        // lose behaviour; only show the graceful state when there is no model.
        setState(() {
          m.previewRefreshing = false;
          m.previewUnavailable = (m.modelUrl == null || m.modelUrl!.isEmpty);
        });
      }
    }
  }

  /// Ensures a conversation exists on the backend, creating it on first use.
  /// Returns its server id, or null if persistence is unavailable.
  Future<String?> _ensurePersisted(_Conversation conv) async {
    if (!_backendChatAvailable) return null;
    if (conv.serverId != null) return conv.serverId;
    try {
      final created = await r2vAiChat.createChat(
        title: conv.title == "New chat" ? null : conv.title,
      );
      conv.serverId = created.id;
      conv.messagesLoaded = true; // freshly created: nothing to fetch
      return created.id;
    } catch (_) {
      _backendChatAvailable = false;
      return null;
    }
  }

  /// Persists a single message (best-effort) under the given conversation.
  Future<void> _persistMessage(
    _Conversation conv, {
    required String role,
    String? text,
    String? modelUrl,
    String? jobId,
    Map<String, dynamic>? meta,
  }) async {
    final sid = await _ensurePersisted(conv);
    if (sid == null) return;
    try {
      await r2vAiChat.addMessage(
        sid,
        role: role,
        text: text,
        modelUrl: modelUrl,
        jobId: jobId,
        meta: meta ?? const {},
      );
    } catch (_) {
      // Best-effort; the bubble is already shown locally.
    }
  }

  _Conversation? _convOf(_ChatMessage message) {
    for (final c in _conversations) {
      if (c.messages.contains(message)) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Post a generated AI model to the marketplace (Phase 4). Publishing is done
  // server-side from the owned AIJob (by jobId), so it works even if the
  // preview's presigned URL has expired.
  // ---------------------------------------------------------------------------
  Future<void> _openPostToMarketplace(_ChatMessage message) async {
    final jobId = message.jobId;
    if (jobId == null || jobId.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = await showModalBottomSheet<MarketplaceAsset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostToMarketplaceSheet(
        jobId: jobId,
        isDark: isDark,
        defaultTitle: _suggestAssetTitle(message),
        viewerDomId: 'ai-result-$jobId',
      ),
    );
    if (!mounted || asset == null) return;
    _showPostedSuccessDialog(asset, isDark);
  }

  String _suggestAssetTitle(_ChatMessage message) {
    final conv = _convOf(message);
    final t = conv?.title;
    if (t != null && t.isNotEmpty && t != "New chat") {
      return t.replaceAll("…", "").trim();
    }
    return "AI Generated Model";
  }

  void _showPostedSuccessDialog(MarketplaceAsset asset, bool isDark) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0B0D14) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Posted to Marketplace",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          "“${asset.title}” has been posted. You can find it in the marketplace.",
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Close",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/explore');
            },
            icon: const Icon(Icons.storefront_rounded, size: 18),
            label: const Text("View in Marketplace"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A4FFF),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Loads the current user from the existing `/me` endpoint and derives a
  /// display name: username -> email prefix -> safe fallback. Failures are
  /// swallowed so the AI page keeps working offline / when unauthenticated.
  Future<void> _loadCurrentUser() async {
    try {
      final me = await r2vProfile.me();
      final name = me.username.trim().isNotEmpty
          ? me.username.trim()
          : (me.email.contains('@') ? me.email.split('@').first : me.email.trim());
      if (!mounted || name.isEmpty) return;
      setState(() => _userName = name);
    } catch (_) {
      // Keep the neutral fallback; do not surface an error for a cosmetic label.
    }
  }

  void _newChat() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _conversations.insert(0, _Conversation(id: id, title: "New chat"));
      _activeConversationId = id;
      uploadedImage = null;
      uploadedAudio = null;
      _controller.clear();
      _isSidebarCollapsed = false; // Open sidebar to show the new chat
    });
    _scrollToBottom();
  }

  void _selectChat(String id) {
    setState(() {
      _activeConversationId = id;
      uploadedImage = null;
      uploadedAudio = null;
      _controller.clear();
    });
    _scrollToBottom();
    // Pull this conversation's history from the backend the first time it opens.
    final conv = _conversations.firstWhere((c) => c.id == id, orElse: () => _activeConversation);
    _loadMessagesFor(conv);
  }

  void _deleteChat(String id) {
    if (_conversations.length <= 1) {
      // Last chat: reset it to an empty "New chat". Delete the old server row so
      // its history is gone, then let it re-persist fresh on the next message.
      final only = _conversations[0];
      final oldServerId = only.serverId;
      setState(() {
        only
          ..title = "New chat"
          ..serverId = null
          ..messagesLoaded = true
          ..messages.clear();
        _activeConversationId = only.id;
        uploadedImage = null;
        uploadedAudio = null;
        _controller.clear();
      });
      if (oldServerId != null) _deleteChatOnBackend(oldServerId);
      _scrollToBottom();
      return;
    }

    String? removedServerId;
    setState(() {
      final wasActive = id == _activeConversationId;
      final idx = _conversations.indexWhere((c) => c.id == id);
      if (idx != -1) removedServerId = _conversations[idx].serverId;
      _conversations.removeWhere((c) => c.id == id);

      if (wasActive) {
        _activeConversationId = _conversations.first.id;
        uploadedImage = null;
        uploadedAudio = null;
        _controller.clear();
      }
    });
    if (removedServerId != null) _deleteChatOnBackend(removedServerId!);
    _scrollToBottom();
  }

  Future<void> _deleteChatOnBackend(String serverId) async {
    if (!_backendChatAvailable) return;
    try {
      await r2vAiChat.deleteChat(serverId);
    } catch (_) {
      // Best-effort; local state already reflects the deletion.
    }
  }

  Future<void> _renameChat(String id, bool isDark) async {
    final conv = _conversations.firstWhere((c) => c.id == id);
    final tc = TextEditingController(
      text: conv.title == "New chat" ? "" : conv.title,
    );

    final newTitle = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0B0D14) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            "Rename chat",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          content: TextField(
            controller: tc,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: "Enter a title",
              hintStyle: TextStyle(
                color: isDark ? Colors.white.withOpacity(0.5) : Colors.black38,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.transparent,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFBC70FF)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withOpacity(0.8)
                      : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final v = tc.text.trim();
                Navigator.pop(ctx, v.isEmpty ? null : v);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A4FFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: isDark ? 0 : 4,
              ),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (newTitle == null) return;
    setState(() => conv.title = newTitle);
    _persistTitle(conv, newTitle);
  }

  Future<void> _persistTitle(_Conversation conv, String title) async {
    final sid = await _ensurePersisted(conv);
    if (sid == null) return;
    try {
      await r2vAiChat.updateChat(sid, title: title);
    } catch (_) {
      // Best-effort; the rename is already reflected locally.
    }
  }

  /// Mobile chat-history sheet. The desktop left sidebar (_LeftChatSidebar) is
  /// hidden under 900px, so this bottom sheet is how mobile users reach saved
  /// conversations: switch, create, rename and delete — all via the same
  /// handlers desktop uses (_selectChat / _newChat / _renameChat / _deleteChat).
  /// A StatefulBuilder lets the sheet redraw after rename/delete without closing.
  void _openChatHistorySheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              expand: false,
              builder: (ctx, scrollController) {
                return ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF120B26).withOpacity(0.92)
                            : Colors.white.withOpacity(0.96),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28)),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.12)
                              : Colors.black.withOpacity(0.06),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Grab handle.
                          Container(
                            margin: const EdgeInsets.only(top: 10, bottom: 6),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black26,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          // Header: title + New chat.
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 12, 10),
                            child: Row(
                              children: [
                                Icon(Icons.forum_rounded,
                                    size: 20,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Your chats",
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 38,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(sheetCtx);
                                      _newChat();
                                    },
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: const Text("New chat"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8A4FFF),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white.withOpacity(0.10)
                                : Colors.black.withOpacity(0.06),
                          ),
                          // Conversation list (reuses the desktop tile, so the
                          // three-dot rename/delete menu works identically).
                          Expanded(
                            child: _conversations.isEmpty
                                ? Center(
                                    child: Text(
                                      "No chats yet",
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                        10, 8, 10, 16),
                                    itemCount: _conversations.length,
                                    itemBuilder: (context, i) {
                                      final c = _conversations[i];
                                      return _ChatHistoryTile(
                                        title: c.title,
                                        active: c.id == _activeConversationId,
                                        isDark: isDark,
                                        onTap: () {
                                          Navigator.pop(sheetCtx);
                                          _selectChat(c.id);
                                        },
                                        onMenu: (action) async {
                                          switch (action) {
                                            case _ChatMenuAction.rename:
                                              await _renameChat(c.id, isDark);
                                              setSheetState(() {});
                                              break;
                                            case _ChatMenuAction.delete:
                                              _deleteChat(c.id);
                                              setSheetState(() {});
                                              break;
                                          }
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSuggestion(String text) {
    setState(() {
      _controller.text = text;
    });
    _sendMessage();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final image = uploadedImage;
    final audio = uploadedAudio;
    if (text.isEmpty && image == null && audio == null) return;

    // Decide the generation input type from what the user provided.
    // Voice takes priority, then image, otherwise a plain text prompt.
    final GenerationInputType inputType;
    final String userLabel;
    if (audio != null) {
      inputType = GenerationInputType.voice;
      userLabel = text.isEmpty ? "🎤 Voice clip: ${audio.name}" : text;
    } else if (image != null) {
      inputType = GenerationInputType.image;
      userLabel = text.isEmpty ? "[Image uploaded]" : text;
    } else {
      inputType = GenerationInputType.prompt;
      userLabel = text;
    }

    // Encode attachments now, before we clear the input state below.
    String? imageB64;
    final imageBytes = image?.bytes;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      imageB64 = base64Encode(imageBytes);
    }
    String? voiceB64;
    final voiceBytes = audio?.bytes;
    if (voiceBytes != null && voiceBytes.isNotEmpty) {
      voiceB64 = base64Encode(voiceBytes);
    }

    final conv = _activeConversation;
    setState(() {
      conv.messages.add(_ChatMessage(userLabel, image, true));

      if (conv.title == "New chat" && text.isNotEmpty) {
        conv.title = text.length > 28 ? "${text.substring(0, 28)}…" : text;
      }

      // Ask the texture question before kicking off generation. The pending
      // request payload is stashed on the assistant message until the user picks.
      conv.messages.add(
        _ChatMessage("Do you want a textured model, or mesh only?", null, false)
          ..textureChoicePending = true
          ..pendingInputType = inputType
          ..pendingPrompt = text
          ..pendingImageB64 = imageB64
          ..pendingImageName = image?.name
          ..pendingVoiceB64 = voiceB64
          ..pendingVoiceName = audio?.name,
      );

      _controller.clear();
      uploadedImage = null;
      uploadedAudio = null;
    });

    _scrollToBottom();
    // Persist the user's turn (creates the conversation on first message and
    // applies the auto-title). The ephemeral "textured or mesh?" prompt is a UI
    // control and is intentionally NOT persisted; the final assistant result is
    // saved later once generation completes.
    _persistMessage(conv, role: "user", text: userLabel);
  }

  /// Runs once the user picks "with texture" / "mesh only" for a pending request.
  Future<void> _onTextureChoice(_ChatMessage message, bool withTexture) async {
    if (!message.textureChoicePending) return;

    final inputType = message.pendingInputType ?? GenerationInputType.prompt;
    final pendingPrompt = (message.pendingPrompt ?? "").trim();

    // Rebuild the settings payload using the same base64-in-settings convention
    // the backend already understands for inline uploads.
    final settings = <String, dynamic>{};
    if (message.pendingImageB64 != null) {
      settings['image_filename'] = message.pendingImageName ?? 'upload.png';
      settings['image_base64'] = message.pendingImageB64;
    }
    if (message.pendingVoiceB64 != null) {
      settings['voice_filename'] = message.pendingVoiceName ?? 'voice.wav';
      settings['voice_base64'] = message.pendingVoiceB64;
    }

    // The backend stores a non-empty prompt; provide a sensible fallback.
    final prompt = pendingPrompt.isNotEmpty
        ? pendingPrompt
        : (inputType == GenerationInputType.voice
              ? "Voice generation"
              : "Image generation");

    setState(() {
      message
        ..textureChoicePending = false
        ..withTexture = withTexture
        ..isGenerating = true
        ..failed = false
        ..jobStatus = "queued"
        ..progress = 0
        ..stage = "queued"
        ..statusMessage = null
        ..text = "";
      // Free the cached payload now that the request is on its way.
      message.pendingImageB64 = null;
      message.pendingVoiceB64 = null;
    });
    _scrollToBottom();

    try {
      final job = await r2vAiJobs.createJob(
        prompt: prompt,
        inputType: inputType,
        withTexture: withTexture,
        settings: settings,
      );
      message.jobId = job.id; // enables "Post to Marketplace" on this result
      await _pollJobStatus(job.id, message, initialJob: job);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        message
          ..isGenerating = false
          ..failed = true
          ..jobStatus = "failed"
          ..text = "Failed to start generation: ${e.message}";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        message
          ..isGenerating = false
          ..failed = true
          ..jobStatus = "failed"
          ..text = "Failed to start generation. Please try again.";
      });
    }
  }

  Future<void> _pollJobStatus(
    String jobId,
    _ChatMessage message, {
    AiJob? initialJob,
  }) async {
    var currentJob = initialJob;
    var attempts = 0;
    // ~10 min at a 2s cadence; generation can be slow under load.
    const maxAttempts = 300;
    const delay = Duration(seconds: 2);

    // Reflect the very first snapshot immediately.
    if (currentJob != null) {
      setState(() => _applyJobProgress(message, currentJob!));
    }

    while (mounted &&
        attempts < maxAttempts &&
        (currentJob == null || !_isJobComplete(currentJob))) {
      await Future.delayed(delay);
      if (!mounted) return;

      try {
        currentJob = await r2vAiJobs.getJob(jobId);
      } catch (_) {
        attempts++;
        continue;
      }

      if (!mounted) return;

      setState(() => _applyJobProgress(message, currentJob!));
      _scrollToBottom();
      attempts++;
    }

    if (!mounted) return;

    if (currentJob != null && _isJobComplete(currentJob)) {
      // ---- Failure: clear the progress card, show a clean error bubble. ----
      if (currentJob.status == "failed") {
        setState(() {
          message
            ..isGenerating = false
            ..failed = true
            ..jobStatus = "failed"
            ..stage = "failed"
            ..text = _formatJobStatus(
              currentJob!,
              hasDownload: false,
              withTexture: message.withTexture,
            );
        });
        _scrollToBottom();
        return;
      }

      // ---- Success: drop the progress card and show the final model. ----
      setState(() {
        message
          ..isGenerating = false
          ..failed = false
          ..jobStatus = currentJob!.status
          ..progress = 100
          ..stage = "done"
          ..textured = currentJob.textured == true
          ..text = _formatJobStatus(
            currentJob,
            hasDownload: message.modelUrl?.isNotEmpty == true,
            withTexture: message.withTexture,
          );
      });
      _scrollToBottom();
      await _attachModelDownload(jobId, message, currentJob);
      // Persist the finished assistant turn (text + generated model + job link)
      // so it is restored on the next login/reload.
      final conv = _convOf(message);
      if (conv != null) {
        await _persistMessage(
          conv,
          role: "assistant",
          text: message.text,
          modelUrl: message.modelUrl,
          jobId: jobId,
          meta: {
            if (message.withTexture != null) 'with_texture': message.withTexture,
            if (message.textured != null) 'textured': message.textured,
          },
        );
      }
      return;
    }

    // ---- Timed out while still processing. ----
    setState(() {
      final fallback = currentJob ?? initialJob;
      message
        ..isGenerating = false
        ..text = [
          if (fallback != null)
            _formatJobStatus(
              fallback,
              hasDownload: message.modelUrl?.isNotEmpty == true,
              withTexture: message.withTexture,
            ),
          "Still processing. You can check back later in your dashboard.",
        ].join("\n");
    });
    _scrollToBottom();
  }

  /// Mirror a polled job's live progress onto the chat message so the
  /// AiGenerationProgressCard can re-render.
  void _applyJobProgress(_ChatMessage message, AiJob job) {
    message
      ..jobStatus = job.status
      ..progress = job.progress
      ..stage = job.stage
      ..statusMessage = job.message;
    if (job.withTexture != null) {
      message.withTexture = job.withTexture;
    }
  }

  bool _isJobComplete(AiJob job) {
    return job.status == "succeeded" || job.status == "failed";
  }

  String _formatJobStatus(
    AiJob job, {
    bool hasDownload = false,
    String? downloadError,
    bool? withTexture,
  }) {
    // Prefer the backend's value; fall back to the user's choice while queued.
    final wantsTexture = job.withTexture ?? withTexture;
    final buffer = StringBuffer();

    if (job.status == "queued" || job.status == "running") {
      buffer.writeln(
        wantsTexture == false
            ? "Generating mesh-only 3D model…"
            : "Generating textured 3D model…",
      );
      buffer.writeln("Status: ${job.status} (${job.progress}%)");
      return buffer.toString().trimRight();
    }

    if (job.status == "succeeded") {
      // Honest: only call it textured when the backend confirms the final GLB
      // is actually textured — never just because the user requested texture.
      final isTextured = job.textured == true;
      buffer.writeln("Model type: ${isTextured ? 'Textured' : 'Mesh only'}");
      if (wantsTexture == true && !isTextured) {
        buffer.writeln(
          "Note: texture was requested but the model came back untextured.",
        );
      }
      if (hasDownload) {
        buffer.writeln("Your model is ready. Preview it below or download it.");
      } else if (downloadError != null && downloadError.isNotEmpty) {
        buffer.writeln(
          "Model ready, but the download link failed: $downloadError",
        );
      } else {
        buffer.writeln("Your model is ready. Fetching the preview…");
      }
      return buffer.toString().trimRight();
    }

    if (job.status == "failed") {
      buffer.writeln("Generation failed.");
      if (job.error != null && job.error!.isNotEmpty) {
        buffer.writeln("Error: ${job.error}");
      }
      return buffer.toString().trimRight();
    }

    buffer.writeln("Status: ${job.status} (${job.progress}%)");
    return buffer.toString().trimRight();
  }

  Future<void> _attachModelDownload(
    String jobId,
    _ChatMessage message,
    AiJob job,
  ) async {
    if (message.modelUrl?.isNotEmpty == true) return;
    try {
      final url = await r2vAiJobs.downloadGlb(jobId);
      if (!mounted) return;
      if (url.isEmpty) {
        setState(
          () => message.text = _formatJobStatus(
            job,
            hasDownload: false,
            downloadError: "Missing download URL",
            withTexture: message.withTexture,
          ),
        );
        return;
      }
      setState(() {
        message.modelUrl = url;
        message.textured = job.textured == true;
        message.text = _formatJobStatus(
          job,
          hasDownload: true,
          withTexture: message.withTexture,
        );
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => message.text = _formatJobStatus(
          job,
          hasDownload: false,
          downloadError: e.message,
          withTexture: message.withTexture,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => message.text = _formatJobStatus(
          job,
          hasDownload: false,
          downloadError: "Unable to fetch download link",
          withTexture: message.withTexture,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null) {
      setState(() {
        uploadedImage = result.files.first;
        uploadedAudio = null; // image and voice are mutually exclusive inputs
      });
    }
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (result != null) {
      setState(() {
        uploadedAudio = result.files.first;
        uploadedImage = null; // image and voice are mutually exclusive inputs
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _chatSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isWide = MediaQuery.of(context).size.width >= 900;

    // Dynamically check theme
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0C0414)
          : const Color(0xFFF8FAFC),
      // Body extends behind the floating LumaBar so the page background flows
      // beneath it (no flat strip). The mobile composer is padded up by the
      // bar's footprint below so the glass pill never covers the chat input.
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. The Interactive Particle Background (Base Layer)
          Positioned.fill(child: MeshyParticleBackground(isDark: isDark)),

          // 2. The Glowing Blobs from the React design (Blurred overlay)
          Positioned.fill(child: _ReactHeroBackground(isDark: isDark)),

          // 3. The UI
          SafeArea(
            child: isWide
                ? _buildWide(context, isDark)
                : _buildMobile(context, isDark),
          ),

          // 4. Mobile-only global section nav as a floating overlay (NOT
          // bottomNavigationBar, so no solid strip is reserved). Desktop keeps
          // its top nav.
          if (!isWide)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: R2VSectionNav(currentIndex: 1),
            ),
        ],
      ),
    );
  }

  Widget _buildWide(BuildContext context, bool isDark) {
    final w = MediaQuery.of(context).size.width;
    final double rightMaxWidth = w > 1500 ? 1500 : w;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: _GlassTopBar(
            activeIndex: _activeIndex,
            isDark: isDark,
            onProfile: () => Navigator.pushNamed(context, '/profile'),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: _isSidebarCollapsed ? 0 : 310,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: 310,
                      maxWidth: 310,
                      child: _LeftChatSidebar(
                        conversations: _filteredConversations,
                        activeId: _activeConversationId,
                        isDark: isDark,
                        onToggleSidebar: () =>
                            setState(() => _isSidebarCollapsed = true),
                        onNewChat: _newChat,
                        onSelect: _selectChat,
                        userName: _userName,
                        searchController: _chatSearchController,
                        onSearchChanged: (v) => setState(() => _chatSearch = v),
                        onRename: (id) => _renameChat(id, isDark),
                        onDelete: _deleteChat,
                        onUserMenu: (action) {
                          switch (action) {
                            case _UserMenuAction.profile:
                              Navigator.pushNamed(context, '/profile');
                              break;
                            case _UserMenuAction.settings:
                              Navigator.pushNamed(context, '/settings');
                              break;
                            case _UserMenuAction.newChat:
                              _newChat();
                              break;
                          }
                        },
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: _isSidebarCollapsed ? 0 : 14,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: rightMaxWidth),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.white.withOpacity(0.8),
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _activeConversation.messages.isEmpty
                                      ? _HeroEmptyState(
                                          onSuggestionTap: _handleSuggestion,
                                          isDark: isDark,
                                        )
                                      : _ChatPanel(
                                          messages:
                                              _activeConversation.messages,
                                          controller: _scrollController,
                                          isDark: isDark,
                                          onTextureChoice: _onTextureChoice,
                                          onPostToMarketplace:
                                              _openPostToMarketplace,
                                          padding: const EdgeInsets.fromLTRB(
                                            22,
                                            18,
                                            22,
                                            140,
                                          ),
                                        ),
                                ),
                                // Floating Expand Button (Visible only when sidebar is collapsed)
                                if (_isSidebarCollapsed)
                                  Positioned(
                                    top: 16,
                                    left: 16,
                                    child: Tooltip(
                                      message: "Open sidebar",
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(
                                            sigmaX: 10,
                                            sigmaY: 10,
                                          ),
                                          child: InkWell(
                                            onTap: () => setState(
                                              () => _isSidebarCollapsed = false,
                                            ),
                                            child: Container(
                                              height: 42,
                                              width: 42,
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white.withOpacity(
                                                        0.1,
                                                      )
                                                    : Colors.white.withOpacity(
                                                        0.6,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.white
                                                            .withOpacity(0.1)
                                                      : Colors.white,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.menu_rounded,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 14,
                                  right: 14,
                                  bottom: 14,
                                  child: _inputBar(isDark),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(BuildContext context, bool isDark) {
    return Column(
      children: [
        AppBar(
          title: Text(
            _activeConversation.title == "New chat"
                ? "AI Studio"
                : _activeConversation.title,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
          // Top-left history button. The desktop conversation sidebar is hidden
          // under 900px, so this opens the mobile chat-history sheet — the way
          // mobile users reach, switch, rename and delete saved chats.
          leading: IconButton(
            tooltip: "Chat history",
            onPressed: () => _openChatHistorySheet(isDark),
            icon: Icon(
              Icons.forum_rounded,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          actions: [
            IconButton(
              tooltip: "New chat",
              onPressed: _newChat,
              icon: Icon(
                Icons.add_rounded,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        Expanded(
          child: _activeConversation.messages.isEmpty
              ? _HeroEmptyState(
                  onSuggestionTap: _handleSuggestion,
                  isDark: isDark,
                )
              : _ChatPanel(
                  messages: _activeConversation.messages,
                  controller: _scrollController,
                  isDark: isDark,
                  onTextureChoice: _onTextureChoice,
                  onPostToMarketplace: _openPostToMarketplace,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                ),
        ),
        Padding(
          // Lift the composer above the floating LumaBar (footprint) so the
          // glass pill floats over the background, never over the input.
          padding: const EdgeInsets.fromLTRB(
              14, 0, 14, 12 + R2VSectionNav.barFootprint),
          child: _inputBar(isDark),
        ),
      ],
    );
  }

  Widget _inputBar(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (uploadedImage != null)
          Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12, left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.white,
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: uploadedImage!.bytes != null
                            ? Image.memory(
                                uploadedImage!.bytes!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                              )
                            : const Icon(
                                Icons.image_rounded,
                                size: 44,
                                color: Colors.grey,
                              ),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          uploadedImage!.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => uploadedImage = null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.15)
                                : Colors.black.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (uploadedAudio != null)
          Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12, left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.white,
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 22,
                        color: isDark
                            ? const Color(0xFFBC70FF)
                            : const Color(0xFF8A4FFF),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          uploadedAudio!.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => uploadedAudio = null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.15)
                                : Colors.black.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                return KeyEventResult.ignored;
              } else {
                _sendMessage();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.15)
                        : Colors.white.withOpacity(0.9),
                  ),
                  boxShadow: isDark
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: "Attach image",
                      onPressed: _pickImage,
                      icon: Icon(
                        Icons.attach_file_rounded,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      hoverColor: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.05),
                    ),
                    IconButton(
                      tooltip: "Attach voice clip",
                      onPressed: _pickAudio,
                      icon: Icon(
                        Icons.mic_none_rounded,
                        color: uploadedAudio != null
                            ? const Color(0xFFBC70FF)
                            : (isDark ? Colors.white54 : Colors.black45),
                      ),
                      hoverColor: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.05),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        // Multiline kept, but capped so the pill can't grow tall.
                        minLines: 1,
                        maxLines: 5,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14.5,
                        ),
                        decoration: InputDecoration(
                          hintText: "Ask R2V to create…",
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black38,
                            fontSize: 14,
                          ),
                          // Fully transparent & borderless so ONLY the outer glass
                          // pill shows. The global inputDecorationTheme is
                          // filled+outlined, which is what painted a second
                          // rounded rectangle (box-in-box) inside the composer.
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.15)
                              : Colors.black.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// THE NEW RESPONSIVE HERO EMPTY STATE
// ==========================================
class _HeroEmptyState extends StatelessWidget {
  final ValueChanged<String> onSuggestionTap;
  final bool isDark;

  const _HeroEmptyState({required this.onSuggestionTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Badge (Glassmorphic)
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.white.withOpacity(0.6),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.white,
                      ),
                      boxShadow: isDark
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black.withOpacity(0.5)
                                : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            "🧠",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Smart 3D solutions powered by R2V",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Headline
              Text(
                "Build Stunning 3D Models",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),

              // Subtitle
              Text(
                "R2V Studio can create amazing 3D assets with a few lines of prompt.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withOpacity(0.8)
                      : Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 48),

              // Suggestion Pills
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _SuggestionPill(
                    "Generate a Sci-Fi Drone",
                    isDark: isDark,
                    onTap: () => onSuggestionTap("Generate a Sci-Fi Drone"),
                  ),
                  _SuggestionPill(
                    "Create a Cyberpunk Car",
                    isDark: isDark,
                    onTap: () => onSuggestionTap("Create a Cyberpunk Car"),
                  ),
                  _SuggestionPill(
                    "Model a Medieval Knight",
                    isDark: isDark,
                    onTap: () => onSuggestionTap("Model a Medieval Knight"),
                  ),
                  _SuggestionPill(
                    "Generate Wooden Chair",
                    isDark: isDark,
                    onTap: () => onSuggestionTap("Generate Wooden Chair"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _SuggestionPill(
    this.label, {
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.white,
              ),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
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
                ? [
                    Colors.white.withOpacity(0.15),
                    Colors.blue.shade300.withOpacity(0.35),
                  ]
                : [
                    const Color(0xFFBC70FF).withOpacity(0.25),
                    const Color(0xFF4895EF).withOpacity(0.25),
                  ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
    );
  }
}
// ==========================================

class _Conversation {
  // Local widget key. Equals [serverId] once persisted; for brand-new local
  // chats it is a temporary client id until the first message creates the row.
  final String id;
  String title;
  final List<_ChatMessage> messages;
  // Backend UUID once this conversation is persisted (null = local-only).
  String? serverId;
  // Whether this conversation's messages have been loaded from the backend.
  bool messagesLoaded = false;

  _Conversation({
    required this.id,
    required this.title,
    List<_ChatMessage>? messages,
    this.serverId,
  }) : messages = messages ?? [];
}

class _ChatMessage {
  String text;
  final PlatformFile? image;
  final bool isUser;
  String? modelUrl;
  // Network URL for an image restored from the backend (e.g. an uploaded image
  // re-presigned via the job). Used when in-memory [image] bytes are gone after
  // a reload. Rendered with Image.network as a fallback to Image.memory.
  String? imageUrl;
  // Restore state for an assistant model preview. While [previewRefreshing] is
  // true we re-presign the model URL from [jobId] and show a loader instead of
  // a possibly-expired viewer src. [previewUnavailable] marks a graceful
  // "couldn't restore" state.
  bool previewRefreshing = false;
  bool previewUnavailable = false;
  // The AIJob that produced this assistant message's model. Used to publish to
  // the marketplace via jobId (works even if the presigned modelUrl expired).
  String? jobId;

  // Texture-choice flow: when true this assistant bubble shows the
  // "with texture / mesh only" buttons instead of plain text.
  bool textureChoicePending = false;
  // Texture preference chosen / requested for this generation.
  bool? withTexture;
  // Whether the finished model is actually textured (from the backend).
  bool? textured;

  // Live AI-generation progress state. While [isGenerating] is true the bubble
  // renders the premium AiGenerationProgressCard instead of the plain text.
  bool isGenerating = false;
  int progress = 0;
  String? stage;
  String? statusMessage;
  String jobStatus = "queued";
  bool failed = false;

  // Stashed request payload, kept until the user makes the texture choice.
  GenerationInputType? pendingInputType;
  String? pendingPrompt;
  String? pendingImageB64;
  String? pendingImageName;
  String? pendingVoiceB64;
  String? pendingVoiceName;

  // ignore: unused_element_parameter
  _ChatMessage(this.text, this.image, this.isUser, {this.modelUrl});
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
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.9),
            ),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 26,
                color: Color(0xFFBC70FF),
              ),
              const SizedBox(width: 8),
              Text(
                "R2V STUDIO",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
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
                    color: isDark
                        ? Colors.white.withOpacity(0.15)
                        : Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    size: 20,
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

// ---------------------------------------------------------
// LEFT SIDEBAR
// ---------------------------------------------------------

enum _ChatMenuAction { rename, delete }

enum _UserMenuAction { profile, settings, newChat }

class _LeftChatSidebar extends StatelessWidget {
  final List<_Conversation> conversations;
  final String activeId;
  final VoidCallback onNewChat;
  final void Function(String id) onSelect;
  final String userName;

  final TextEditingController searchController;
  final void Function(String text) onSearchChanged;

  final Future<void> Function(String id) onRename;
  final void Function(String id) onDelete;
  final void Function(_UserMenuAction action) onUserMenu;
  final bool isDark;
  final VoidCallback onToggleSidebar;

  const _LeftChatSidebar({
    required this.conversations,
    required this.activeId,
    required this.onNewChat,
    required this.onSelect,
    required this.userName,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRename,
    required this.onDelete,
    required this.onUserMenu,
    required this.isDark,
    required this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.8),
            ),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              // Header Row with New Chat and Close Sidebar button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: onNewChat,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text("New chat"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8A4FFF),
                            foregroundColor: Colors.white,
                            elevation: isDark ? 0 : 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: "Close sidebar",
                      child: InkWell(
                        onTap: onToggleSidebar,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 46,
                          width: 46,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            Icons.menu_open_rounded,
                            color: isDark ? Colors.white70 : Colors.black54,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: isDark
                            ? Colors.white.withOpacity(0.5)
                            : Colors.black38,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: onSearchChanged,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: "Search chats",
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.black38,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                        ),
                      ),
                      if (searchController.text.trim().isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            searchController.clear();
                            onSearchChanged("");
                            FocusScope.of(context).unfocus();
                          },
                          child: Icon(
                            Icons.close_rounded,
                            color: isDark
                                ? Colors.white.withOpacity(0.7)
                                : Colors.black54,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Divider(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.black.withOpacity(0.05),
                height: 1,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  itemCount: conversations.length,
                  itemBuilder: (context, i) {
                    final c = conversations[i];
                    final active = c.id == activeId;

                    return _ChatHistoryTile(
                      title: c.title,
                      active: active,
                      isDark: isDark,
                      onTap: () => onSelect(c.id),
                      onMenu: (action) async {
                        switch (action) {
                          case _ChatMenuAction.rename:
                            await onRename(c.id);
                            break;
                          case _ChatMenuAction.delete:
                            onDelete(c.id);
                            break;
                        }
                      },
                    );
                  },
                ),
              ),
              Divider(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.black.withOpacity(0.05),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.15)
                            : Colors.black.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1E293B),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PopupMenuButton<_UserMenuAction>(
                      tooltip: "More",
                      color: isDark ? const Color(0xFF1C1528) : Colors.white,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: isDark
                            ? Colors.white.withOpacity(0.75)
                            : Colors.black54,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onSelected: onUserMenu,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: _UserMenuAction.profile,
                          child: _MenuRow(
                            icon: Icons.person_outline_rounded,
                            label: "Profile",
                            isDark: isDark,
                          ),
                        ),
                        PopupMenuItem(
                          value: _UserMenuAction.settings,
                          child: _MenuRow(
                            icon: Icons.settings_outlined,
                            label: "Settings",
                            isDark: isDark,
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: _UserMenuAction.newChat,
                          child: _MenuRow(
                            icon: Icons.add_rounded,
                            label: "New chat",
                            isDark: isDark,
                          ),
                        ),
                      ],
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

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: isDark ? Colors.white : Colors.black87, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
      ],
    );
  }
}

class _ChatHistoryTile extends StatelessWidget {
  final String title;
  final bool active;
  final VoidCallback onTap;
  final void Function(_ChatMenuAction action) onMenu;
  final bool isDark;

  const _ChatHistoryTile({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onMenu,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? (isDark
                    ? Colors.white.withOpacity(0.15)
                    : Colors.black.withOpacity(0.04))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? (isDark ? Colors.white.withOpacity(0.1) : Colors.transparent)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              color: isDark
                  ? Colors.white.withOpacity(active ? 0.9 : 0.5)
                  : (active ? const Color(0xFF1E293B) : Colors.black54),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withOpacity(active ? 1.0 : 0.7)
                      : (active ? const Color(0xFF1E293B) : Colors.black87),
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<_ChatMenuAction>(
              tooltip: "Chat options",
              color: isDark ? const Color(0xFF1C1528) : Colors.white,
              icon: Icon(
                Icons.more_vert_rounded,
                color: isDark ? Colors.white.withOpacity(0.7) : Colors.black54,
                size: 18,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: onMenu,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ChatMenuAction.rename,
                  child: _MenuRow(
                    icon: Icons.edit_rounded,
                    label: "Rename",
                    isDark: isDark,
                  ),
                ),
                PopupMenuItem(
                  value: _ChatMenuAction.delete,
                  child: _MenuRow(
                    icon: Icons.delete_outline_rounded,
                    label: "Delete",
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// CHAT PANEL
// ---------------------------------------------------------

class _ChatPanel extends StatelessWidget {
  final List<_ChatMessage> messages;
  final ScrollController controller;
  final EdgeInsets? padding;
  final bool isDark;
  final void Function(_ChatMessage message, bool withTexture) onTextureChoice;
  final void Function(_ChatMessage message) onPostToMarketplace;

  const _ChatPanel({
    required this.messages,
    required this.controller,
    required this.isDark,
    required this.onTextureChoice,
    required this.onPostToMarketplace,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding ?? const EdgeInsets.fromLTRB(20, 18, 20, 18),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: _ChatBubble(
            message: msg,
            isDark: isDark,
            onTextureChoice: onTextureChoice,
            onPostToMarketplace: onPostToMarketplace,
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isDark;
  final void Function(_ChatMessage message, bool withTexture) onTextureChoice;
  final void Function(_ChatMessage message) onPostToMarketplace;

  const _ChatBubble({
    required this.message,
    required this.isDark,
    required this.onTextureChoice,
    required this.onPostToMarketplace,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    // While a generation job is active, replace the plain bubble (and the old
    // "Typing..." indicator) with the premium live progress card.
    if (!isUser && message.isGenerating) {
      return AiGenerationProgressCard(
        progress: message.progress,
        stage: message.stage,
        message: message.statusMessage,
        withTexture: message.withTexture,
        status: message.jobStatus,
        isDark: isDark,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isUser
            ? (isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF1E293B))
            : (isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.8)),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(isUser ? 0.0 : 0.05),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.image != null &&
              (message.image!.bytes?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  message.image!.bytes!,
                  height: 170,
                  width: 320,
                  fit: BoxFit.cover,
                ),
              ),
            )
          // Restored uploaded image (in-memory bytes are gone after reload):
          // render the re-presigned network URL instead.
          else if (message.imageUrl?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  message.imageUrl!,
                  height: 170,
                  width: 320,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 170,
                      width: 320,
                      alignment: Alignment.center,
                      color: Colors.black.withOpacity(0.05),
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (context, _, __) => Container(
                    height: 170,
                    width: 320,
                    alignment: Alignment.center,
                    color: Colors.black.withOpacity(0.05),
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ),
              ),
            ),
          Text(
            message.text,
            style: TextStyle(
              color: isUser
                  ? (isDark ? Colors.black : Colors.white)
                  : (isDark ? Colors.white : Colors.black87),
              fontSize: 14.5,
              height: 1.35,
              fontWeight: isUser ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          // Texture choice: shown before generation starts.
          if (!isUser && message.textureChoicePending) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TextureChoiceButton(
                  label: "Yes, with texture",
                  icon: Icons.brush_rounded,
                  primary: true,
                  isDark: isDark,
                  onTap: () => onTextureChoice(message, true),
                ),
                _TextureChoiceButton(
                  label: "No, mesh only",
                  icon: Icons.view_in_ar_rounded,
                  primary: false,
                  isDark: isDark,
                  onTap: () => onTextureChoice(message, false),
                ),
              ],
            ),
          ],
          // Restoring a saved model preview: re-presigning the URL from jobId.
          if (!isUser && message.previewRefreshing) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  color: isDark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.black.withOpacity(0.05),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Restoring preview…",
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          // Graceful state when the model could not be restored.
          if (!isUser &&
              !message.previewRefreshing &&
              message.previewUnavailable &&
              (message.modelUrl == null || message.modelUrl!.isEmpty)) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  color: isDark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.black.withOpacity(0.05),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.view_in_ar_outlined,
                        color: isDark ? Colors.white38 : Colors.black26,
                        size: 30,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Preview unavailable",
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (!isUser &&
              !message.previewRefreshing &&
              message.modelUrl?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            _TextureBadge(
              textured: message.textured ?? message.withTexture ?? false,
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  color: isDark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.black.withOpacity(0.05),
                  child: GestureDetector(
                    // Absorb drags so rotating the generated model doesn't
                    // scroll the chat/page behind it.
                    onVerticalDragUpdate: (_) {},
                    onHorizontalDragUpdate: (_) {},
                    child: ModelViewer(
                      key: ValueKey(message.modelUrl),
                      // Stable DOM id lets the Post-to-Marketplace modal capture
                      // a thumbnail from this exact preview (current angle).
                      id: message.jobId != null && message.jobId!.isNotEmpty
                          ? 'ai-result-${message.jobId}'
                          : null,
                      src: message.modelUrl!,
                      backgroundColor: Colors.transparent,
                      cameraControls: true,
                      autoRotate: true,
                      environmentImage: "neutral",
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final url = message.modelUrl;
                if (url == null || url.isEmpty) return;
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: Icon(
                Icons.download_rounded,
                size: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
              label: Text(
                "Download GLB",
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                backgroundColor: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            // Publish the generated model straight to the marketplace. Uses the
            // jobId (not the presigned modelUrl) so it works even after expiry.
            if (message.jobId != null && message.jobId!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => onPostToMarketplace(message),
                icon: const Icon(Icons.storefront_rounded, size: 18),
                label: const Text("Post to Marketplace"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A4FFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: isDark ? 0 : 2,
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                final url = message.modelUrl;
                if (url == null || url.isEmpty) return;
                Navigator.pushNamed(
                  context,
                  '/talent/post-project',
                  arguments: {
                    'title': 'Professional cleanup for generated 3D model',
                    'attachments': [url],
                  },
                );
              },
              icon: Icon(
                Icons.handyman_outlined,
                size: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
              label: Text(
                'Need professional cleanup?',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Chat-style "with texture / mesh only" choice button.
class _TextureChoiceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final bool isDark;
  final VoidCallback onTap;

  const _TextureChoiceButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = primary
        ? const Color(0xFF8A4FFF)
        : (isDark
              ? Colors.white.withOpacity(0.12)
              : Colors.black.withOpacity(0.05));
    final Color fg = primary
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF1E293B));

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small badge labelling the finished model as Textured or Mesh only.
class _TextureBadge extends StatelessWidget {
  final bool textured;
  final bool isDark;

  const _TextureBadge({required this.textured, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final Color accent = textured
        ? const Color(0xFF8A4FFF)
        : const Color(0xFF4895EF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(isDark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            textured ? Icons.brush_rounded : Icons.view_in_ar_rounded,
            size: 15,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            textured ? "Textured" : "Mesh only",
            style: TextStyle(
              color: accent,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// MESHY BACKGROUND (The Interactive Base layer)
// ---------------------------------------------------------
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

class _MeshyBgCoreState extends State<_MeshyBgCore>
    with SingleTickerProviderStateMixin {
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
        if (p.pos.dx < 0 || p.pos.dx > _size.width)
          p.vel = Offset(-p.vel.dx, p.vel.dy);
        if (p.pos.dy < 0 || p.pos.dy > _size.height)
          p.vel = Offset(p.vel.dx, -p.vel.dy);
        p.pos = Offset(
          p.pos.dx.clamp(0.0, _size.width),
          p.pos.dy.clamp(0.0, _size.height),
        );
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
      final pos = Offset(
        _rng.nextDouble() * s.width,
        _rng.nextDouble() * s.height,
      );
      final speed = 8 + _rng.nextDouble() * 18;
      final ang = _rng.nextDouble() * pi * 2;
      final vel = Offset(cos(ang), sin(ang)) * speed;
      final r = 1.2 + _rng.nextDouble() * 1.9;
      return _Particle(pos: pos, vel: vel, radius: r);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
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
      },
    );
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

    glowBlob(
      center + wobble,
      280,
      isDark ? const Color(0xFF8A4FFF) : const Color(0xFFA855F7),
      isDark ? 0.18 : 0.12,
    );
    glowBlob(
      Offset(size.width * 0.25, size.height * 0.70) +
          Offset(cos(time * 0.35) * 35, sin(time * 0.32) * 28),
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
      dotPaint.color = isDark
          ? Colors.white.withOpacity(0.12)
          : const Color(0xFF8A4FFF).withOpacity(0.25);
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

// ---------------------------------------------------------------------------
// Post-to-Marketplace modal. Premium glass sheet matching the R2V theme. On
// submit it calls POST /ai/jobs/{jobId}/asset and pops with the created asset.
// ---------------------------------------------------------------------------
class _PostToMarketplaceSheet extends StatefulWidget {
  final String jobId;
  final bool isDark;
  final String defaultTitle;
  // DOM id of the chat's result model-viewer, used to capture a thumbnail at
  // the angle the user framed in the preview (web only).
  final String? viewerDomId;

  const _PostToMarketplaceSheet({
    required this.jobId,
    required this.isDark,
    required this.defaultTitle,
    this.viewerDomId,
  });

  @override
  State<_PostToMarketplaceSheet> createState() => _PostToMarketplaceSheetState();
}

class _PostToMarketplaceSheetState extends State<_PostToMarketplaceSheet> {
  // Match the existing manual marketplace create form options.
  static const List<String> _categories = [
    "Characters", "Objects", "Vehicles", "Environments", "Stylized", "Realistic",
  ];
  static const List<String> _styles = ["Realistic", "Stylized", "CGI", "Low Poly"];
  static const List<String> _currencies = ["usd", "egp"];

  late final TextEditingController _title =
      TextEditingController(text: widget.defaultTitle);
  final TextEditingController _description = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _price = TextEditingController(text: "0");

  String _category = "Objects";
  String _style = "Stylized";
  String _currency = "usd";
  bool _isPaid = false;
  bool _publishNow = true;
  // When no thumbnail is captured, fall back to the job's generated preview.
  bool _useGeneratedThumb = true;

  // Captured-from-viewer thumbnail (web). Null until the user captures one.
  Uint8List? _thumbBytes;
  bool _capturing = false;

  bool _submitting = false;
  String? _error;

  bool get _canCapture => kIsWeb && (widget.viewerDomId != null);

  Future<void> _captureThumbnail() async {
    if (!_canCapture || _capturing) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final bytes = await captureModelViewerPng(widget.viewerDomId!);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _capturing = false;
          _error = "Couldn't capture the preview. Rotate the model in the chat, then try again.";
        });
        return;
      }
      setState(() {
        _thumbBytes = bytes;
        _capturing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = "Thumbnail capture isn't available here.";
      });
    }
  }

  /// Uploads a captured thumbnail via the marketplace presign flow and returns
  /// its object key (null if there is nothing to upload).
  Future<String?> _uploadCapturedThumb() async {
    final bytes = _thumbBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final presign = await r2vMarketplace.presignAssetUpload(
      filename: 'ai-thumbnail.png',
      contentType: 'image/png',
      kind: 'thumb',
    );
    final url = presign['url'] ?? '';
    final key = presign['key'] ?? '';
    if (url.isEmpty || key.isEmpty) {
      throw Exception('Could not prepare thumbnail upload');
    }
    await r2vMarketplace.uploadToPresignedUrl(url, bytes, contentType: 'image/png');
    return key;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = "Please enter a title.");
      return;
    }
    final price = _isPaid ? (int.tryParse(_price.text.trim()) ?? 0) : 0;
    final tags = _tags.text
        .split(",")
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Upload a captured thumbnail first (if any); otherwise fall back to the
      // job's generated preview server-side.
      final thumbKey = await _uploadCapturedThumb();
      final asset = await r2vMarketplace.createFromAiJob(
        jobId: widget.jobId,
        title: title,
        description: _description.text.trim(),
        tags: tags,
        category: _category,
        style: _style,
        isPaid: _isPaid && price > 0,
        price: price,
        currency: _currency,
        publish: _publishNow,
        includeThumbnail: thumbKey == null && _useGeneratedThumb,
        thumbObjectKey: thumbKey,
      );
      if (!mounted) return;
      Navigator.pop(context, asset);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't post to the marketplace. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final fg = isDark ? Colors.white : const Color(0xFF1E293B);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.86,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF120B1E).withOpacity(0.96)
                  : Colors.white.withOpacity(0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded, color: Color(0xFF8A4FFF)),
                        const SizedBox(width: 10),
                        Text(
                          "Post to Marketplace",
                          style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _label("Title", fg),
                    _field(_title, isDark, hint: "Name your model"),
                    const SizedBox(height: 12),
                    _label("Description", fg),
                    _field(_description, isDark, hint: "Describe it (optional)", maxLines: 3),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label("Category", fg),
                              _dropdown(_category, _categories, (v) => setState(() => _category = v), isDark),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label("Style", fg),
                              _dropdown(_style, _styles, (v) => setState(() => _style = v), isDark),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _label("Tags", fg),
                    _field(_tags, isDark, hint: "comma, separated, tags (optional)"),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF8A4FFF),
                      title: Text("Paid model", style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                      subtitle: Text("Charge a price instead of free",
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 12)),
                      value: _isPaid,
                      onChanged: _submitting ? null : (v) => setState(() => _isPaid = v),
                    ),
                    if (_isPaid)
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label("Price", fg),
                                _field(_price, isDark, hint: "0", number: true),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label("Currency", fg),
                                _dropdown(_currency, _currencies, (v) => setState(() => _currency = v), isDark),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    _label("Thumbnail", fg),
                    _thumbnailSection(isDark, fg),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF8A4FFF),
                      title: Text("Publish now", style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                      subtitle: Text(_publishNow ? "Visible in the marketplace immediately" : "Save as a draft in your listings",
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 12)),
                      value: _publishNow,
                      onChanged: _submitting ? null : (v) => setState(() => _publishNow = v),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8A4FFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text("Post to Marketplace",
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailSection(bool isDark, Color fg) {
    final muted = isDark ? Colors.white54 : Colors.black45;

    // A thumbnail has been captured: show it with retake/remove actions.
    if (_thumbBytes != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                child: Image.memory(_thumbBytes!, fit: BoxFit.contain, alignment: Alignment.center),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _submitting || _capturing ? null : _captureThumbnail,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text("Retake"),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _submitting ? null : () => setState(() => _thumbBytes = null),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text("Remove"),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_canCapture) ...[
          OutlinedButton.icon(
            onPressed: _submitting || _capturing ? null : _captureThumbnail,
            icon: _capturing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8A4FFF)),
                  )
                : const Icon(Icons.camera_alt_rounded, size: 18),
            label: Text(_capturing ? "Capturing…" : "Capture from preview"),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Rotate the generated model in the chat to your preferred angle, then capture.",
            style: TextStyle(color: muted, fontSize: 11.5),
          ),
          const SizedBox(height: 6),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF8A4FFF),
          title: Text("Use generated preview as thumbnail", style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          subtitle: Text("Used when you don't capture one", style: TextStyle(color: muted, fontSize: 12)),
          value: _useGeneratedThumb,
          onChanged: _submitting ? null : (v) => setState(() => _useGeneratedThumb = v),
        ),
      ],
    );
  }

  Widget _label(String text, Color fg) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(color: fg.withOpacity(0.85), fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  Widget _field(TextEditingController c, bool isDark,
      {String? hint, int maxLines = 1, bool number = false}) {
    return TextField(
      controller: c,
      enabled: !_submitting,
      maxLines: maxLines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8A4FFF)),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1C1528) : Colors.white,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: _submitting ? null : (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}
