class DebateHistoryItem {
  const DebateHistoryItem({
    required this.debateId,
    required this.topic,
    required this.status,
    required this.opponentLabel,
    required this.outcomeLabel,
    required this.createdAt,
  });

  final String debateId;
  final String topic;
  final String status;
  final String opponentLabel;
  final String outcomeLabel;
  final DateTime? createdAt;
}
