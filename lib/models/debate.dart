import 'package:cloud_firestore/cloud_firestore.dart';

class Debate {
  final String id;
  final int durationSeconds;
  final int roundIndex;
  final String activeSpeakerId;
  final bool isTimerRunning;
  final Timestamp startTime;

  Debate({
    required this.id,
    required this.durationSeconds,
    required this.roundIndex,
    required this.activeSpeakerId,
    required this.isTimerRunning,
    required this.startTime,
  });

  static int readRoundIndexFromMap(
    Map<String, dynamic> data, {
    int fallback = 1,
  }) {
    final dynamic canonical = data['roundIndex'];
    if (canonical is int) return canonical;

    // Keep temporary legacy fallback for old documents during rollout.
    final dynamic legacyCurrent = data['currentRound'];
    if (legacyCurrent is int) return legacyCurrent;

    final dynamic legacyRound = data['round'];
    if (legacyRound is int) return legacyRound;

    return fallback;
  }

  factory Debate.fromMap(String id, Map<String, dynamic> data) {
    return Debate(
      id: id,
      durationSeconds: data['durationSeconds'] ?? data['durationSec'] ?? 60,
      roundIndex: readRoundIndexFromMap(data),
      activeSpeakerId: data['activeSpeakerId'] ?? '',
      isTimerRunning: data['isTimerRunning'] ?? false,
      startTime: data['startedAt'] ?? data['startTime'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'durationSeconds': durationSeconds,
      'roundIndex': roundIndex,
      'activeSpeakerId': activeSpeakerId,
      'isTimerRunning': isTimerRunning,
      'startedAt': startTime,
    };
  }
}
