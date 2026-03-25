import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/name_utils.dart';

class DebateMessagesList extends StatelessWidget {
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

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _messageBubble(Map<String, dynamic> data, AppLocalizations l10n) {
    final senderName = firstNonEmptyName(
      [data['senderName'], data['sender']],
      fallback: l10n.anonymous,
    );
    final senderId = data['senderId'] ?? '';
    final text = data['text'] ?? '';
    final createdAt =
        data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;
    final isLeft = senderId == fighter1Id || senderName == fighter1Id;

    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isLeft ? const Color(0xFFFFFFFF) : const Color(0xFFDCF8C6),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isLeft ? 6 : 18),
            bottomRight: Radius.circular(isLeft ? 18 : 6),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              senderName.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.25,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatTime(createdAt),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('debates')
          .doc(debateId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context)!;
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
                  style: const TextStyle(color: Colors.white54),
                ),
              )
            : ListView.builder(
                key: const PageStorageKey('messages-list'),
                reverse: true,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data =
                      docs[index].data() as Map<String, dynamic>? ?? {};
                  return _messageBubble(data, l10n);
                },
              );

        if (!showWaitingTurn) return list;

        return Column(
          children: [
            Expanded(child: list),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  waitingText.isNotEmpty ? waitingText : l10n.waitingYourTurn,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.bold,
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
