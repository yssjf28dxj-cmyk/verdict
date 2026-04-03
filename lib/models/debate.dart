import 'package:cloud_firestore/cloud_firestore.dart';

class Debate {
  final String id;
  final String topic;
  final String debateType;
  final String fighter1;
  final String fighter2;
  final String opponentId;
  final String creatorId;
  final String creationMode;
  final String invitedUserId;
  final String fighter1Name;
  final String fighter2Name;
  final int votes1;
  final int votes2;
  final String status;
  final int roundIndex;
  final int totalRounds;
  final String activeSpeakerId;
  final bool isTimerRunning;
  final bool isRoundActive;
  final Timestamp? startTime;
  final Map<String, dynamic> termsProposalCreator;
  final Map<String, dynamic> termsProposalAccepter;
  final Map<String, dynamic> termsResolved;
  final String termsResolverVersion;
  final String termsResolutionStatus;
  
  // Dynamic duration property derived from resolution
  final int durationSeconds;

  Debate({
    required this.id,
    this.topic = '',
    this.debateType = 'open',
    this.fighter1 = '',
    this.fighter2 = '',
    this.opponentId = '',
    this.creatorId = '',
    this.creationMode = 'public_feed',
    this.invitedUserId = '',
    this.fighter1Name = '',
    this.fighter2Name = '',
    this.votes1 = 0,
    this.votes2 = 0,
    this.status = 'waiting',
    this.roundIndex = 1,
    this.totalRounds = 3,
    this.activeSpeakerId = '',
    this.isTimerRunning = false,
    this.isRoundActive = false,
    this.startTime,
    this.termsProposalCreator = const {},
    this.termsProposalAccepter = const {},
    this.termsResolved = const {},
    this.termsResolverVersion = 'v1_mean_nearest_strict',
    this.termsResolutionStatus = '',
    this.durationSeconds = 60,
  });

  static int readRoundIndexFromMap(
    Map<String, dynamic> data, {
    int fallback = 1,
  }) {
    final dynamic canonical = data['roundIndex'];
    if (canonical is int) return canonical;

    final dynamic legacyCurrent = data['currentRound'];
    if (legacyCurrent is int) return legacyCurrent;

    final dynamic legacyRound = data['round'];
    if (legacyRound is int) return legacyRound;

    return fallback;
  }
  
  static int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }
  
  static bool _asBool(dynamic value, bool fallback) {
    if (value is bool) return value;
    return fallback;
  }

  factory Debate.fromMap(String id, Map<String, dynamic> data) {
    String f1 = (data['fighter1'] is String) ? data['fighter1'] as String : '';
    String f2 = (data['fighter2'] is String) ? data['fighter2'] as String : '';
    final oppId = (data['opponentId'] is String) ? data['opponentId'] as String : '';
    final cId = (data['creatorId'] is String) ? data['creatorId'] as String : '';
    
    if (f1.trim().isEmpty) f1 = cId;
    if (f2.trim().isEmpty) f2 = oppId;
    
    final int dur = _asInt(data['durationSeconds'] ?? data['durationSec'], 60);

    return Debate(
      id: id,
      topic: (data['topic'] is String) ? data['topic'] as String : '',
      debateType: (data['debateType'] is String) ? data['debateType'] as String : 'open',
      fighter1: f1,
      fighter2: f2,
      opponentId: oppId,
      creatorId: cId,
      creationMode: (data['creationMode'] is String) ? data['creationMode'] as String : 'public_feed',
      invitedUserId: (data['invitedUserId'] is String) ? data['invitedUserId'] as String : '',
      fighter1Name: (data['fighter1Name'] is String) ? data['fighter1Name'] as String : '',
      fighter2Name: (data['fighter2Name'] is String) ? data['fighter2Name'] as String : '',
      votes1: _asInt(data['votes1'], 0),
      votes2: _asInt(data['votes2'], 0),
      status: (data['status'] is String) ? data['status'] as String : 'waiting',
      roundIndex: readRoundIndexFromMap(data),
      totalRounds: _asInt(data['totalRounds'], 3),
      activeSpeakerId: (data['activeSpeakerId'] is String) ? data['activeSpeakerId'] as String : '',
      isTimerRunning: _asBool(data['isTimerRunning'], false),
      isRoundActive: _asBool(data['isRoundActive'], false),
      startTime: data['startTime'] is Timestamp ? data['startTime'] as Timestamp : (data['startedAt'] is Timestamp ? data['startedAt'] as Timestamp : null),
      termsProposalCreator: data['termsProposalCreator'] is Map ? Map<String, dynamic>.from(data['termsProposalCreator'] as Map) : const {},
      termsProposalAccepter: data['termsProposalAccepter'] is Map ? Map<String, dynamic>.from(data['termsProposalAccepter'] as Map) : const {},
      termsResolved: data['termsResolved'] is Map ? Map<String, dynamic>.from(data['termsResolved'] as Map) : const {},
      termsResolverVersion: (data['termsResolverVersion'] ?? 'v1_mean_nearest_strict').toString(),
      termsResolutionStatus: (data['termsResolutionStatus'] ?? '').toString(),
      durationSeconds: dur,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'debateType': debateType,
      'fighter1': fighter1,
      'fighter2': fighter2,
      'opponentId': opponentId,
      'creatorId': creatorId,
      'creationMode': creationMode,
      'invitedUserId': invitedUserId,
      'fighter1Name': fighter1Name,
      'fighter2Name': fighter2Name,
      'votes1': votes1,
      'votes2': votes2,
      'status': status,
      'durationSeconds': durationSeconds,
      'roundIndex': roundIndex,
      'totalRounds': totalRounds,
      'activeSpeakerId': activeSpeakerId,
      'isTimerRunning': isTimerRunning,
      'isRoundActive': isRoundActive,
      if (startTime != null) 'startedAt': startTime,
      if (startTime != null) 'startTime': startTime,
      'termsProposalCreator': termsProposalCreator,
      'termsProposalAccepter': termsProposalAccepter,
      'termsResolved': termsResolved,
      'termsResolverVersion': termsResolverVersion,
      'termsResolutionStatus': termsResolutionStatus,
    };
  }
}
