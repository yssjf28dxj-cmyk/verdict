import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/name_utils.dart';

class DebateMessagesList extends StatefulWidget {
  final String debateId;
  final String fighter1Id;
  final bool showWaitingTurn;
  final String waitingText;

  const DebateMessagesList({
    super.key,
    required this.debateId,
    required this.fighter1Id,
    this.showWaitingTurn = false,
    this.waitingText = '',
  });

  @override
  State<DebateMessagesList> createState() => _DebateMessagesListState();
}

class _DebateMessagesListState extends State<DebateMessagesList> {
  final Set<String> _animatedMessageIds = <String>{};

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildAvatar({
    required String senderName,
    required bool isMine,
  }) {
    final safeName = senderName.trim().isEmpty ? '?' : senderName.trim();
    final initial = safeName.substring(0, 1).toUpperCase();
    final color = isMine ? const Color(0xFF3A77FF) : const Color(0xFF8A8F9F);

    return CircleAvatar(
      radius: 12,
      backgroundColor: color.withValues(alpha: 0.22),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _messageBubble({
    required String messageId,
    required Map<String, dynamic> data,
    required bool isMine,
    required AppLocalizations l10n,
  }) {
    final senderName = firstNonEmptyName(
      [data['senderName'], data['sender']],
      fallback: l10n.anonymous,
    );
    final text = (data['text'] ?? '').toString();
    final createdAt =
        data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;
    final bubbleGradient = isMine
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x663A77FF), Color(0x33224488)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x332A2D35), Color(0x221B1E26)],
          );
    final bubbleBorder =
        isMine ? const Color(0xAA67A2FF) : Colors.white.withValues(alpha: 0.22);

    final bubble = ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMine ? 20 : 6),
        bottomRight: Radius.circular(isMine ? 6 : 20),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: bubbleGradient,
            border: Border.all(color: bubbleBorder, width: 1.1),
            boxShadow: [
              BoxShadow(
                color:
                    isMine ? const Color(0x553A77FF) : const Color(0x3310141C),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.28,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatTime(createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.48),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final rowChild = Row(
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMine) _buildAvatar(senderName: senderName, isMine: isMine),
        if (!isMine) const SizedBox(width: 7),
        Flexible(
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2, right: 2),
                child: Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.3,
                    color: Colors.white.withValues(alpha: 0.54),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              bubble,
            ],
          ),
        ),
        if (isMine) const SizedBox(width: 7),
        if (isMine) _buildAvatar(senderName: senderName, isMine: isMine),
      ],
    );

    final shouldAnimate = !_animatedMessageIds.contains(messageId);
    if (!shouldAnimate) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: rowChild,
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('msg-enter-$messageId'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.elasticOut,
      onEnd: () {
        if (!mounted) return;
        _animatedMessageIds.add(messageId);
      },
      builder: (context, value, child) {
        final slide = (1 - value) * 38;
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, slide),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: rowChild,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('debates')
          .doc(widget.debateId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context)!;
        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFFA500),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final list = docs.isEmpty
            ? Center(
                child: Text(
                  l10n.noMessagesYet,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
                ),
              )
            : ListView.builder(
                key: const PageStorageKey('messages-list'),
                reverse: true,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final senderId = (data['senderId'] ?? '').toString();
                  final isMine =
                      currentUid.isNotEmpty && senderId == currentUid;

                  return _messageBubble(
                    messageId: doc.id,
                    data: data,
                    isMine: isMine,
                    l10n: l10n,
                  );
                },
              );

        if (!widget.showWaitingTurn) return list;

        return Column(
          children: [
            Expanded(child: list),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.waitingText.isNotEmpty
                      ? widget.waitingText
                      : l10n.waitingYourTurn,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
