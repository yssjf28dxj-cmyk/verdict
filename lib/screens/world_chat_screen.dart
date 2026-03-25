import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/name_utils.dart';
import '../utils/rank_utils.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import 'public_profile_screen.dart';

class WorldChatScreen extends StatefulWidget {
  const WorldChatScreen({super.key});

  @override
  State<WorldChatScreen> createState() => _WorldChatScreenState();
}

class _WorldChatScreenState extends State<WorldChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  late final Stream<QuerySnapshot> _chatStream;
  double _keyboardInset = 0;
  int _lastMessageCount = 0;
  bool _autoScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatStream = FirebaseFirestore.instance
        .collection('world_messages')
        .orderBy('timestamp')
        .limitToLast(100)
        .snapshots();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final newInset = view.viewInsets.bottom / view.devicePixelRatio;
    if (newInset != _keyboardInset) {
      setState(() {
        _keyboardInset = newInset;
      });
      if (_scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = _controller.text.trim();
    if (user == null || text.isEmpty) return;

    // Save text before clearing, so we can restore on error
    final savedText = text;
    setState(() => _sending = true);
    _controller.clear();

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sendWorldMessage',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );
      await callable.call({'text': savedText});
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } on FirebaseFunctionsException catch (e) {
      // Restore text on error so user can retry
      _controller.text = savedText;
      if (!mounted) return;
      final errorDetail = e.message ?? e.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Send failed: $errorDetail'),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      // Catch network errors, timeouts, etc.
      _controller.text = savedText;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Send failed: $e'),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scheduleAutoScrollIfNeeded(int currentCount) {
    if (currentCount <= _lastMessageCount) return;
    _lastMessageCount = currentCount;
    if (_autoScrollScheduled) return;
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollScheduled = false;
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _safeSenderLabel(AppLocalizations l10n, dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return l10n.anonymous;
    final looksLikeTechnicalId = value.length >= 20 && !value.contains(' ');
    if (looksLikeTechnicalId) return l10n.anonymous;
    return value;
  }

  void _openUserProfile(String senderId, String senderName) {
    if (senderId.isEmpty) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (senderId == currentUid) return; // Don't open own profile from chat

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PublicProfileScreen(
          uid: senderId,
          publicId: '',
          name: senderName,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: VerdictStyle.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(l10n.worldChatTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: _keyboardInset),
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _chatStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            '${l10n.errorPrefix}: ${snapshot.error}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      final docs = snapshot.data?.docs ?? [];
                      _scheduleAutoScrollIfNeeded(docs.length);
                      return ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: docs.length,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 10),
                        itemBuilder: (context, i) {
                          final data = docs[i].data() as Map<String, dynamic>;
                          final senderId =
                              (data['senderId'] ?? '').toString();
                          final isMe =
                              user != null && senderId == user.uid;
                          final senderName = _safeSenderLabel(
                            l10n,
                            firstNonEmptyName(
                              [
                                data['senderName'],
                                data['displayName'],
                                data['sender'],
                              ],
                              fallback: l10n.anonymous,
                            ),
                          );
                          final double senderRating =
                              (data['senderRating'] is num)
                                  ? (data['senderRating'] as num).toDouble()
                                  : 0;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.82,
                              ),
                              child: GlassCard(
                                enableBlur: false,
                                borderRadius: BorderRadius.circular(20),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Message text
                                    Text(
                                      (data['text'] ?? '').toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    // Sender row: name + rank badge + time
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Clickable name
                                        InkWell(
                                          onTap: isMe
                                              ? null
                                              : () => _openUserProfile(
                                                    senderId, senderName),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                senderName,
                                                style: TextStyle(
                                                  color: isMe
                                                      ? VerdictStyle.fighterBlue
                                                      : VerdictStyle.accentGold
                                                          .withValues(
                                                              alpha: 0.8),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (!isMe) ...[
                                                const SizedBox(width: 2),
                                                Icon(
                                                  Icons
                                                      .arrow_forward_ios_rounded,
                                                  size: 9,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Rank badge
                                        if (senderRating > 0)
                                          RankBadge(
                                            rating: senderRating,
                                            showLabel: false,
                                            iconSize: 11,
                                          ),
                                        const SizedBox(width: 6),
                                        if (data['timestamp'] != null)
                                          Text(
                                            _formatTime(data['timestamp']),
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.35),
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: GlassCard(
                      enableBlur: false,
                      borderRadius: BorderRadius.circular(24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: l10n.messageHint,
                                hintStyle:
                                    const TextStyle(color: Colors.white54),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color(0x662A3147),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: _sending ? null : _sendMessage,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: _sending
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: VerdictStyle.accentGold,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send,
                                        color: VerdictStyle.accentGold,
                                        size: 28,
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
        ],
      ),
    );
  }
}
