import 'package:cloud_firestore/cloud_firestore.dart';

class DebateHistoryItem {
  const DebateHistoryItem({
    required this.debateId,
    required this.topic,
    required this.status,
    required this.opponentLabel,
    required this.outcomeLabel,
    required this.createdAt,
  });

  factory DebateHistoryItem.fromData(
      String id, Map<String, dynamic> data, String uid) {
    final first = data['fighter1'] == uid;
    final opponent = data[first ? 'fighter2Name' : 'fighter1Name'];
    final winner = data['winner'];
    final status = data['status'] is String ? data['status'] as String : '';
    final side = first ? 'fighter1' : 'fighter2';
    final outcome = status != 'finished'
        ? 'LIVE'
        : winner == 'draw'
            ? 'DRAW'
            : winner == side
                ? 'WIN'
                : ['fighter1', 'fighter2'].contains(winner)
                    ? 'LOSS'
                    : 'FINISHED';
    final timestamp = data['createdAt'];
    return DebateHistoryItem(
        debateId: id,
        topic: data['topic'] is String ? data['topic'] as String : '',
        status: status,
        opponentLabel: opponent is String ? opponent : '',
        outcomeLabel: outcome,
        createdAt: timestamp is Timestamp ? timestamp.toDate() : null);
  }

  final String debateId;
  final String topic;
  final String status;
  final String opponentLabel;
  final String outcomeLabel;
  final DateTime? createdAt;
}
