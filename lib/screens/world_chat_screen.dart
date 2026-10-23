import '../utils/pending_message_request.dart';
import 'package:verdict/firebase_session.dart';
import 'package:verdict/firestore_database.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/name_utils.dart';
import '../utils/rank_utils.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class WorldChatScreen extends StatefulWidget {
  const WorldChatScreen({super.key});

  @override
  State<WorldChatScreen> createState() => _WorldChatScreenState();
}

class _WorldChatScreenState extends State<WorldChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  final _pendingRequest = PendingMessageRequest();
  late final Stream<QuerySnapshot> _chatStream;
  int _lastMessageCount = 0;
  bool _autoScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _chatStream = appFirestore
        .collection('world_messages')
        .orderBy('timestamp')
        .limitToLast(100)
        .snapshots();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  Future<void> _sendMessage() async {
    if (_sending) return;
    final user = appAuth.currentUser;
    final text = _controller.text.trim();
    if (user == null || text.isEmpty) return;
    final request = _pendingRequest.forText(text);
    setState(() => _sending = true);
    try {
      final callable = appFunctions.httpsCallable(
        'sendWorldMessage',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );
      await callable.call({'text': request.text, 'clientRequestId': request.id});
      _pendingRequest.confirmed(request);
      if (!mounted) return;
      // Preserve a draft typed after this request; never restore over newer input.
      if (_controller.text.trim() == request.text) _controller.clear();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${AppLocalizations.of(context)!.errorPrefix}: ${error.message ?? error.code}'),
        duration: const Duration(seconds: 4),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.messageSendFailed),
        duration: const Duration(seconds: 4),
      ));
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
    final currentUid = appAuth.currentUser?.uid ?? '';
    if (senderId == currentUid) return; // Don't open own profile from chat

    context.push(
      '/public-profile',
      extra: {
        'uid': senderId,
        'publicId': '',
        'name': senderName,
      },
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
    final user = appAuth.currentUser;
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
          Column(
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

                          double bottomPadding = 12.0;
                          if (i < docs.length - 1) {
                            final nextData = docs[i + 1].data() as Map<String, dynamic>;
                            final nextSenderId = (nextData['senderId'] ?? '').toString();
                            if (nextSenderId == senderId) {
                                bottomPadding = 4.0;
                            }
                          }

                          final bubbleColor = isMe ? const Color(0xFFFFD700) : const Color(0xFF2A2A2A);

                          final senderRow = InkWell(
                            onTap: isMe
                                ? null
                                : () => _openUserProfile(senderId, senderName),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  senderName,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.52),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                if (!isMe) ...[
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 8,
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ],
                                if (senderRating > 0) ...[
                                  const SizedBox(width: 6),
                                  RankBadge(
                                    rating: senderRating,
                                    showLabel: false,
                                    iconSize: 10,
                                  ),
                                ],
                              ],
                            ),
                          );

                          return Padding(
                            padding: EdgeInsets.only(bottom: bottomPadding),
                            child: Row(
                              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
                                        child: senderRow,
                                      ),
                                      Container(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context).size.width * 0.82,
                                        ),
                                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                        decoration: BoxDecoration(
                                          color: bubbleColor,
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(18),
                                            topRight: const Radius.circular(18),
                                            bottomLeft: Radius.circular(isMe ? 18 : 4),
                                            bottomRight: Radius.circular(isMe ? 4 : 18),
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              (data['text'] ?? '').toString(),
                                              style: TextStyle(
                                                color: isMe ? Colors.black : Colors.white,
                                                fontSize: 15.5,
                                                height: 1.28,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            if (data['timestamp'] != null)
                                              Text(
                                                _formatTime(data['timestamp']),
                                                style: TextStyle(
                                                  color: isMe ? Colors.black54 : Colors.white.withValues(alpha: 0.42),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
          ],
        ),
      );
    }
}
