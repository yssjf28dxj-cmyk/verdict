# VERDICT Диагностика

Дата: 2026-03-23

## 1) Все ошибки из консоли / терминала

### flutter analyze
Analyzing verdict...
No issues found! (ran in 3.9s)

### VS Code Problems / get_errors
No errors found.

### Runtime errors
Явные runtime errors из активной консоли в рамках этого сбора не зафиксированы.

## 2) Полное содержимое файлов

### lib/screens/debate_room_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/debate.dart';
import '../painters/chat_pattern_painter.dart';
import '../widgets/debate_messages_list.dart';
import '../services/referee_service.dart';
import '../services/debate_alert_service.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/name_utils.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';

import 'result_screen.dart';

class DebateRoomScreen extends StatefulWidget {
  final String debateId;

  const DebateRoomScreen({
    super.key,
    required this.debateId,
  });

  @override
  State<DebateRoomScreen> createState() => _DebateRoomScreenState();
}

class _DebateRoomScreenState extends State<DebateRoomScreen> {
  static const List<int> _durationOptions = <int>[
    30,
    60,
    90,
    120,
    180,
    300,
    420,
    600,
  ];
  static const List<int> _roundOptions = <int>[1, 3, 5];
  static const int _advanceJitterWindowMs = 1800;

  void _refreshMyVoteStatus() {
    // TODO: Implement vote status refresh logic if needed.
    // This is a stub to prevent errors if the method is missing.
  }

  final TextEditingController _messageController = TextEditingController();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  int votes1 = 0;
  int votes2 = 0;

  String topic = '';
  String debateType = 'open';
  String fighter1 = '';
  String fighter2 = '';
  String opponentId = '';
  String creatorId = '';
  String fighter1Name = '';
  String fighter2Name = '';
  String status = 'active';
  String activeSpeakerId = '';
  int roundIndex = 1;
  int totalRounds = 3;
  bool isRoundActive = true;
  int pendingPenaltySecondsForMe = 0;
  bool hasVotedThisRound = false;
  int votedSideThisRound = 0;
  int _voteStatusRoundIndex = -1;
  bool isTimerRunning = false;
  Timestamp? startTime;
  String creationMode = 'public_feed';
  String invitedUserId = '';
  bool _isAcceptingPending = false;
  int _termsCreatorDuration = 180;
  int _termsCreatorRounds = 3;
  int _termsAccepterDuration = 180;
  int _termsAccepterRounds = 3;
  int _termsResolvedDuration = 180;
  int _termsResolvedRounds = 3;
  String _termsPolicyVersion = 'v1_mean_nearest_strict';
  bool _termsAreResolved = false;

  bool isLoading = true;
  bool movedToResult = false;
  bool _accessDeniedHandled = false;

  Timer? _roundCountdownTicker;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? debateSub;
  DateTime? _roundEndsAtLocal;

  String currentUserId = '';
  String currentUserName = '';

  late final ValueNotifier<int> _timeLeftNotifier;
  late final ValueNotifier<bool> _dangerZoneNotifier;
  late final ValueNotifier<bool> _dangerPulseNotifier;

  bool _advanceInFlight = false;
  bool _advancePending = false;
  bool _isSendingMessage = false;
  int _advanceAttemptToken = 0;
  int _lastAdvanceRoundAttempt = -1;
  DateTime? _lastAdvanceAttemptAt;
  int _lastDangerHapticSecond = -1;
  String _lastHydratedFighter1Uid = '';
  String _lastHydratedFighter2Uid = '';

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  int _sanitizeDuration(dynamic value, int fallback) {
    final candidate =
        value is int ? value : (value is num ? value.toInt() : fallback);
    return _durationOptions.contains(candidate) ? candidate : fallback;
  }

  int _sanitizeRounds(dynamic value, int fallback) {
    final candidate =
        value is int ? value : (value is num ? value.toInt() : fallback);
    return _roundOptions.contains(candidate) ? candidate : fallback;
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  bool _asBool(dynamic value, bool fallback) {
    if (value is bool) return value;
    return fallback;
  }

  String _normalizeStatus(dynamic value, {String fallback = 'waiting'}) {
    final normalized = (value ?? '').toString().trim();
    if (normalized.isEmpty) return fallback;
    if (normalized == 'live') return 'active';
    if (normalized == 'waiting' ||
        normalized == 'active' ||
        normalized == 'finished') {
      return normalized;
    }
    return fallback;
  }

  int _readRoundIndex(Map<String, dynamic> data, {int fallback = 1}) {
    return Debate.readRoundIndexFromMap(data, fallback: fallback);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainderSeconds = seconds % 60;
    return '$minutes:${remainderSeconds.toString().padLeft(2, '0')}';
  }

  int _effectiveRoundsFromData(Map<String, dynamic> data, int fallback) {
    final resolved = data['termsResolved'];
    if (resolved is Map) {
      final v = _sanitizeRounds(resolved['totalRounds'], fallback);
      if (v > 0) return v;
    }
    final creator = data['termsProposalCreator'];
    if (creator is Map) {
      final v = _sanitizeRounds(creator['totalRounds'], fallback);
      if (v > 0) return v;
    }
    return _sanitizeRounds(data['totalRounds'], fallback);
  }

  String _safeWriteHint(AppLocalizations l10n) {
    final raw = l10n.messageHint.trim();
    if (raw.isEmpty || raw.toUpperCase() == 'NOT_FOUND') {
      return 'Write a message...';
    }
    return raw;
  }

  String _safeLocalizedText(String raw, String fallback) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.toUpperCase() == 'NOT_FOUND') {
      return fallback;
    }
    return normalized;
  }

  String _effectiveInvitedUid(Map<String, dynamic> data) {
    final invited = (data['invitedUserId'] ?? '').toString();
    if (invited.isNotEmpty) return invited;
    final opponent = (data['opponentId'] ?? '').toString();
    final creator = (data['creatorId'] ?? '').toString();
    if (opponent.isNotEmpty && opponent != creator) return opponent;
    final maybeFighter2 = (data['fighter2'] ?? '').toString();
    final mode = (data['creationMode'] ?? 'public_feed').toString();
    if (mode == 'direct_invite' && _hasRealOpponentId(creator, maybeFighter2)) {
      return maybeFighter2;
    }
    return '';
  }

  bool _isDebateParticipant(Map<String, dynamic> data) {
    final uid = currentUserId.trim();
    if (uid.isEmpty) return false;

    final creator = (data['creatorId'] ?? '').toString();
    final opponent = (data['opponentId'] ?? '').toString();
    final f1 = (data['fighter1'] ?? '').toString();
    final f2 = (data['fighter2'] ?? '').toString();
    final effectiveF1 = f1.isNotEmpty ? f1 : creator;
    final effectiveF2 = f2.isNotEmpty ? f2 : opponent;
    final invited = (data['invitedUserId'] ?? '').toString();
    final invitedList = _stringList(data['invitedUserIds']);
    final effectiveInvitedUid = _effectiveInvitedUid(data);

    return uid == effectiveF1 ||
        uid == effectiveF2 ||
        uid == creator ||
        uid == opponent ||
        uid == invited ||
        uid == effectiveInvitedUid ||
        invitedList.contains(uid);
  }

  Future<void> _hydrateFighterNamesFromUsers() async {
    final f1Uid =
        fighter1.trim().isNotEmpty ? fighter1.trim() : creatorId.trim();
    final f2Uid =
        fighter2.trim().isNotEmpty ? fighter2.trim() : opponentId.trim();

    final shouldHydrateF1 = f1Uid.isNotEmpty &&
        fighter1Name.trim().isEmpty &&
        _lastHydratedFighter1Uid != f1Uid;
    final shouldHydrateF2 = f2Uid.isNotEmpty &&
        fighter2Name.trim().isEmpty &&
        _lastHydratedFighter2Uid != f2Uid;
    if (!shouldHydrateF1 && !shouldHydrateF2) return;

    _lastHydratedFighter1Uid = f1Uid;
    _lastHydratedFighter2Uid = f2Uid;

    var nextF1Name = fighter1Name;
    var nextF2Name = fighter2Name;

    if (shouldHydrateF1) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(f1Uid)
            .get();
        final data = snap.data();
        final derived = deriveNeutralName(
          displayName: sanitizePublicName(data?['name']),
          email: sanitizePublicName(data?['email']),
          uid: f1Uid,
        );
        if (derived.trim().isNotEmpty) {
          nextF1Name = derived.trim();
        }
      } catch (_) {}
    }

    if (shouldHydrateF2) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(f2Uid)
            .get();
        final data = snap.data();
        final derived = deriveNeutralName(
          displayName: sanitizePublicName(data?['name']),
          email: sanitizePublicName(data?['email']),
          uid: f2Uid,
        );
        if (derived.trim().isNotEmpty) {
          nextF2Name = derived.trim();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    if (nextF1Name != fighter1Name || nextF2Name != fighter2Name) {
      setState(() {
        fighter1Name = nextF1Name;
        fighter2Name = nextF2Name;
      });
    }
  }

  bool _canAccessDebateData(Map<String, dynamic> data) {
    final uid = currentUserId.trim();
    final visibility = (data['visibilityMode'] ?? 'public').toString();
    final creationMode = (data['creationMode'] ?? 'public_feed').toString();
    final approvedUserIds = _stringList(data['accessApprovedUserIds']);

    final isParticipant = _isDebateParticipant(data);

    if (visibility == 'private') return isParticipant;
    if (visibility == 'request_only') {
      if (uid.isEmpty) return false;
      return isParticipant || approvedUserIds.contains(uid);
    }
    if (creationMode == 'direct_invite' && !isParticipant) return false;
    return true;
  }

  void _handleAccessDeniedAndExit() {
    if (_accessDeniedHandled || !mounted) return;
    _accessDeniedHandled = true;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.accessRestricted)),
    );
    Navigator.of(context).maybePop();
  }

  @override
  void initState() {
    super.initState();
    _timeLeftNotifier = ValueNotifier<int>(60);
    _dangerZoneNotifier = ValueNotifier<bool>(false);
    _dangerPulseNotifier = ValueNotifier<bool>(false);
    _bootstrapCurrentUserIdentity();
    _startRoundCountdownTicker();
    _loadDebate();
  }

  void _bootstrapCurrentUserIdentity() {
    final user = FirebaseAuth.instance.currentUser;
    currentUserId = user?.uid ?? '';
    currentUserName = _bestEffortName(user);
  }

  String _bestEffortName(User? user) {
    final fromMemory = sanitizePublicName(currentUserName);
    if (fromMemory.isNotEmpty) return fromMemory;

    return deriveNeutralName(
      displayName: user?.displayName ?? '',
      email: user?.email ?? '',
      uid: user?.uid ?? '',
    );
  }

  Future<void> _hydrateUserNameFromFirestore() async {
    if (currentUserId.isEmpty) return;

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      final name = sanitizePublicName(userSnap.data()?['name']);
      if (name.isEmpty) return;
      if (!mounted) return;
      setState(() {
        currentUserName = name;
      });
    } catch (_) {
      // Keep auth-based fallback name when profile lookup fails.
    }
  }

  void _startRoundCountdownTicker() {
    _roundCountdownTicker?.cancel();
    _roundCountdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (status == 'finished') {
        _timeLeftNotifier.value = 0;
        _dangerZoneNotifier.value = false;
        _dangerPulseNotifier.value = false;
        return;
      }

      final remaining = _remainingSecondsFromRoundEnd();
      _timeLeftNotifier.value = remaining;

      if (DebateAlertService.dangerFlashEnabled &&
          remaining > 0 &&
          remaining <= 10) {
        _dangerZoneNotifier.value = true;
        _dangerPulseNotifier.value = !_dangerPulseNotifier.value;
        if (_lastDangerHapticSecond != remaining) {
          _lastDangerHapticSecond = remaining;
          HapticFeedback.lightImpact();
        }
      } else {
        _dangerZoneNotifier.value = false;
        _dangerPulseNotifier.value = false;
        _lastDangerHapticSecond = -1;
      }
    });
  }

  int _remainingSecondsFromRoundEnd() {
    final end = _roundEndsAtLocal;
    if (end == null) return 0;
    final diff = end.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  DateTime? _resolveRoundEndsAtFromData(Map<String, dynamic> data) {
    final rawRoundEndsAt = data['roundEndsAt'];
    if (rawRoundEndsAt is Timestamp) {
      return rawRoundEndsAt.toDate();
    }

    final rawStart = data['startedAt'] ?? data['startTime'];
    DateTime? startedAt;
    if (rawStart is Timestamp) {
      startedAt = rawStart.toDate();
    } else if (rawStart is DateTime) {
      startedAt = rawStart;
    }
    if (startedAt == null) return null;

    final fallbackDuration =
        _termsResolvedDuration > 0 ? _termsResolvedDuration : 180;
    final roundDuration = _sanitizeDuration(
      data['roundDurationSeconds'] ?? data['durationSeconds'],
      fallbackDuration,
    );
    return startedAt.add(Duration(seconds: roundDuration));
  }

  bool _shouldAttemptAdvanceFromClient({
    required String currentStatus,
    required bool roundActive,
  }) {
    if (currentStatus != 'active') return false;
    if (!roundActive) return false;
    return true;
  }

  void _syncRoundCountdownFromData(
    Map<String, dynamic> data,
    String newStatus,
  ) {
    if (newStatus == 'finished' || newStatus != 'active') {
      _roundEndsAtLocal = null;
      _timeLeftNotifier.value = 0;
      return;
    }

    final resolvedRoundEnd = _resolveRoundEndsAtFromData(data);
    if (resolvedRoundEnd != null) {
      _roundEndsAtLocal = resolvedRoundEnd;
      _timeLeftNotifier.value = _remainingSecondsFromRoundEnd();
      return;
    }

    _roundEndsAtLocal = null;
    _timeLeftNotifier.value = 0;
  }

  Future<void> _loadDebate() async {
    final ref =
        FirebaseFirestore.instance.collection('debates').doc(widget.debateId);
    _bootstrapCurrentUserIdentity();
    DocumentSnapshot<Map<String, dynamic>> snap;
    Map<String, dynamic>? data;

    try {
      snap = await ref.get().timeout(const Duration(seconds: 12));
      data = snap.data();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.accessRestricted)),
      );
      Navigator.of(context).maybePop();
      return;
    }

    if (!mounted) return;

    if (data == null) {
      setState(() {
        isLoading = false;
        topic = '';
        debateType = 'open';
        fighter1 = currentUserId;
        fighter2 = '';
        opponentId = '';
        creatorId = currentUserId;
        fighter1Name = currentUserName;
        fighter2Name = '';
        votes1 = 0;
        votes2 = 0;
        status = 'waiting';
        roundIndex = 1;
        totalRounds = 3;
        activeSpeakerId = '';
        isRoundActive = false;
        isTimerRunning = false;
        startTime = null;
      });
      return;
    }

    if (!_canAccessDebateData(data)) {
      setState(() {
        isLoading = false;
      });
      _handleAccessDeniedAndExit();
      return;
    }

    topic = (data['topic'] is String) ? data['topic'] as String : '';
    debateType =
        (data['debateType'] is String) ? data['debateType'] as String : 'open';
    fighter1 = (data['fighter1'] is String) ? data['fighter1'] as String : '';
    fighter2 = (data['fighter2'] is String) ? data['fighter2'] as String : '';
    opponentId =
        (data['opponentId'] is String) ? data['opponentId'] as String : '';
    creatorId =
        (data['creatorId'] is String) ? data['creatorId'] as String : '';
    if (fighter1.trim().isEmpty) fighter1 = creatorId;
    if (fighter2.trim().isEmpty) fighter2 = opponentId;
    creationMode = (data['creationMode'] is String)
        ? data['creationMode'] as String
        : 'public_feed';
    invitedUserId = (data['invitedUserId'] is String)
        ? data['invitedUserId'] as String
        : '';
    fighter1Name = sanitizePublicName(data['fighter1Name']);
    fighter2Name = sanitizePublicName(data['fighter2Name']);
    votes1 = _asInt(data['votes1'], 0);
    votes2 = _asInt(data['votes2'], 0);
    status = _normalizeStatus(data['status'], fallback: 'waiting');
    roundIndex = _readRoundIndex(data, fallback: 1);
    totalRounds = _effectiveRoundsFromData(data, totalRounds);
    activeSpeakerId = (data['activeSpeakerId'] is String)
        ? data['activeSpeakerId'] as String
        : '';
    isTimerRunning = _asBool(data['isTimerRunning'], false);
    isRoundActive = _asBool(data['isRoundActive'], isRoundActive);
    startTime = data['startTime'];
    final creatorProposal = data['termsProposalCreator'] is Map
        ? data['termsProposalCreator'] as Map
        : const {};
    final accepterProposal = data['termsProposalAccepter'] is Map
        ? data['termsProposalAccepter'] as Map
        : const {};
    final resolvedTerms =
        data['termsResolved'] is Map ? data['termsResolved'] as Map : const {};
    _termsCreatorDuration = _sanitizeDuration(
      creatorProposal['roundDurationSeconds'],
      _sanitizeDuration(
          data['roundDurationSeconds'] ?? data['durationSeconds'], 180),
    );
    _termsCreatorRounds = _sanitizeRounds(
      creatorProposal['totalRounds'],
      _sanitizeRounds(data['totalRounds'], 3),
    );
    _termsAccepterDuration = _sanitizeDuration(
      accepterProposal['roundDurationSeconds'],
      _termsCreatorDuration,
    );
    _termsAccepterRounds = _sanitizeRounds(
      accepterProposal['totalRounds'],
      _termsCreatorRounds,
    );
    _termsResolvedDuration = _sanitizeDuration(
      resolvedTerms['roundDurationSeconds'],
      _termsCreatorDuration,
    );
    _termsResolvedRounds = _sanitizeRounds(
      resolvedTerms['totalRounds'],
      _termsCreatorRounds,
    );
    _termsPolicyVersion =
        (data['termsResolverVersion'] ?? 'v1_mean_nearest_strict').toString();
    _termsAreResolved =
        (data['termsResolutionStatus'] ?? '').toString() == 'resolved';

    await _hydrateUserNameFromFirestore();
    await _hydrateFighterNamesFromUsers();

    _syncRoundCountdownFromData(data, status);

    setState(() {
      isLoading = false;
    });

    // Если roundEndsAt ещё не выставлен (новая схема), попросим сервер
    // инициализировать первый ход/таймер. Это один безопасный вызов.
    if (data['roundEndsAt'] == null &&
        _shouldAttemptAdvanceFromClient(
          currentStatus: status,
          roundActive: isRoundActive,
        )) {
      await _attemptAdvanceRoundOrFinish();
    }

    debateSub = ref.snapshots().listen((doc) {
      final liveData = doc.data() ?? {};
      final previousRound = roundIndex;

      if (!mounted) return;

      if (!_canAccessDebateData(liveData)) {
        _handleAccessDeniedAndExit();
        return;
      }

      final newStatus = _normalizeStatus(liveData['status'] ?? status,
          fallback: status == 'finished' ? 'finished' : 'waiting');
      _syncRoundCountdownFromData(liveData, newStatus);

      setState(() {
        votes1 = _asInt(liveData['votes1'], votes1);
        votes2 = _asInt(liveData['votes2'], votes2);
        status = newStatus;
        fighter1 = (liveData['fighter1'] ?? fighter1).toString();
        fighter2 = (liveData['fighter2'] ?? fighter2).toString();
        opponentId = (liveData['opponentId'] ?? opponentId).toString();
        creatorId = (liveData['creatorId'] ?? creatorId).toString();
        if (fighter1.trim().isEmpty) {
          fighter1 = creatorId;
        }
        if (fighter2.trim().isEmpty) {
          fighter2 = opponentId;
        }
        creationMode = (liveData['creationMode'] ?? creationMode).toString();
        invitedUserId = (liveData['invitedUserId'] ?? invitedUserId).toString();
        fighter1Name = sanitizePublicName(
          liveData['fighter1Name'] ?? fighter1Name,
        );
        fighter2Name = sanitizePublicName(
          liveData['fighter2Name'] ?? fighter2Name,
        );
        activeSpeakerId =
            (liveData['activeSpeakerId'] ?? activeSpeakerId).toString();
        roundIndex = _readRoundIndex(liveData, fallback: roundIndex);
        totalRounds = _effectiveRoundsFromData(liveData, totalRounds);
        isRoundActive = _asBool(liveData['isRoundActive'], isRoundActive);
        final creatorProposal = liveData['termsProposalCreator'] is Map
            ? liveData['termsProposalCreator'] as Map
            : const {};
        final accepterProposal = liveData['termsProposalAccepter'] is Map
            ? liveData['termsProposalAccepter'] as Map
            : const {};
        final resolvedTerms = liveData['termsResolved'] is Map
            ? liveData['termsResolved'] as Map
            : const {};
        _termsCreatorDuration = _sanitizeDuration(
          creatorProposal['roundDurationSeconds'],
          _sanitizeDuration(
              liveData['roundDurationSeconds'] ?? liveData['durationSeconds'],
              _termsCreatorDuration),
        );
        _termsCreatorRounds = _sanitizeRounds(
          creatorProposal['totalRounds'],
          _sanitizeRounds(liveData['totalRounds'], _termsCreatorRounds),
        );
        _termsAccepterDuration = _sanitizeDuration(
          accepterProposal['roundDurationSeconds'],
          _termsAccepterDuration,
        );
        _termsAccepterRounds = _sanitizeRounds(
          accepterProposal['totalRounds'],
          _termsAccepterRounds,
        );
        _termsResolvedDuration = _sanitizeDuration(
          resolvedTerms['roundDurationSeconds'],
          _termsResolvedDuration,
        );
        _termsResolvedRounds = _sanitizeRounds(
          resolvedTerms['totalRounds'],
          _termsResolvedRounds,
        );
        _termsPolicyVersion =
            (liveData['termsResolverVersion'] ?? _termsPolicyVersion)
                .toString();
        _termsAreResolved =
            (liveData['termsResolutionStatus'] ?? '').toString() == 'resolved';
        final pending = liveData['pendingPenalty'];
        if (pending is Map && currentUserId.isNotEmpty) {
          final raw = pending[currentUserId];
          pendingPenaltySecondsForMe =
              raw is int ? raw : (raw is num ? raw.toInt() : 0);
        } else {
          pendingPenaltySecondsForMe = 0;
        }
      });

      if (_voteStatusRoundIndex != roundIndex && newStatus != 'finished') {
        if (isViewer) _refreshMyVoteStatus();
      }

      _cancelPendingAdvanceIfNeeded(
        previousRound: previousRound,
        nextRound: roundIndex,
        nextStatus: status,
      );

      _hydrateFighterNamesFromUsers();

      if (_timeLeftNotifier.value == 0 &&
          _shouldAttemptAdvanceFromClient(
            currentStatus: newStatus,
            roundActive: isRoundActive,
          )) {
        _attemptAdvanceRoundOrFinish();
      }

      if (newStatus == 'finished' && !movedToResult) {
        movedToResult = true;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                ResultScreen(debateId: widget.debateId),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        );
      }
    }, onError: (_) {
      _handleAccessDeniedAndExit();
    });
  }

  String get _effectiveCurrentUid {
    if (currentUserId.isNotEmpty) return currentUserId;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  bool get isParticipant {
    final uid = _effectiveCurrentUid;
    if (uid.isEmpty) return false;
    return uid == creatorId ||
        uid == opponentId ||
        uid == fighter1 ||
        uid == fighter2;
  }

  bool get isFighter {
    return isParticipant;
  }

  bool get isViewer {
    return !isFighter;
  }

  bool _hasRealOpponentId(String f1, String f2) {
    final normalized = f2.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized == f1.trim().toLowerCase()) return false;
    return !const {
      'opponent',
      'invited',
      'fighter',
      'оппонент',
      'приглашен',
      'приглашён',
    }.contains(normalized);
  }

  bool get _canAcceptPending {
    if (status != 'waiting') return false;
    final uid = _effectiveCurrentUid;
    if (uid.isEmpty) return false;
    if (uid == creatorId || uid == fighter1) return false;

    final effectiveInvitedUid = _effectiveInvitedUid({
      'invitedUserId': invitedUserId,
      'opponentId': opponentId,
      'creatorId': creatorId,
      'fighter2': fighter2,
      'creationMode': creationMode,
    });
    final isDirectInvite =
        creationMode == 'direct_invite' || effectiveInvitedUid.isNotEmpty;
    if (isDirectInvite) {
      return effectiveInvitedUid.isNotEmpty && uid == effectiveInvitedUid;
    }

    return !_hasRealOpponentId(fighter1, fighter2);
  }

  Future<void> _acceptPendingDebate() async {
    if (_isAcceptingPending || !_canAcceptPending) return;
    final l10n = AppLocalizations.of(context)!;
    final callable = _functions.httpsCallable(
      'acceptDebateInvite',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final payload = {
      'debateId': widget.debateId,
      'proposedRoundDurationSeconds': _termsCreatorDuration,
      'proposedTotalRounds': _termsCreatorRounds,
    };

    setState(() {
      _isAcceptingPending = true;
    });

    try {
      await callable.call(payload);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final retryableCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };
      if (!retryableCodes.contains(e.code)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mapDebateCallableError(
              l10n,
              e,
              fallbackMessage: l10n.acceptChallengeFailed,
            )),
          ),
        );
      } else {
        try {
          await Future.delayed(const Duration(milliseconds: 900));
          await callable.call(payload);
        } on FirebaseFunctionsException catch (retryError) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(mapDebateCallableError(
                l10n,
                retryError,
                fallbackMessage: l10n.acceptChallengeFailed,
              )),
            ),
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.acceptChallengeFailed)),
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.acceptChallengeFailed)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAcceptingPending = false;
        });
      }
    }
  }

  bool get isMyTurn {
    if (!isFighter) return false;
    if (status == 'finished') return false;
    if (!isRoundActive) return false;
    if (activeSpeakerId.trim().isEmpty) return false;
    if (currentUserId.isNotEmpty) return currentUserId == activeSpeakerId;
    return currentUserName == activeSpeakerId;
  }

  int _stableHash(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  void _cancelPendingAdvanceIfNeeded({
    required int previousRound,
    required int nextRound,
    required String nextStatus,
  }) {
    if (!_advancePending) return;
    if (nextStatus == 'finished' || nextRound != previousRound) {
      _advanceAttemptToken++;
      _advancePending = false;
    }
  }

  Future<void> _attemptAdvanceRoundOrFinish() async {
    if (_advanceInFlight || _advancePending) return;
    if (status == 'finished') return;

    final now = DateTime.now();
    final lastAt = _lastAdvanceAttemptAt;
    if (lastAt != null && now.difference(lastAt).inSeconds < 4) {
      return;
    }

    // Дедуп по раунду: если уже пытались для текущего раунда — не спамим.
    if (_lastAdvanceRoundAttempt == roundIndex && lastAt != null) {
      return;
    }

    final plannedRound = roundIndex;
    final attemptToken = ++_advanceAttemptToken;
    final stableUid = _effectiveCurrentUid;
    final hashSeed = stableUid.isNotEmpty ? stableUid : widget.debateId;
    final delayMs = _stableHash(hashSeed) % _advanceJitterWindowMs;

    _advancePending = true;
    _lastAdvanceAttemptAt = now;
    _lastAdvanceRoundAttempt = roundIndex;

    await Future.delayed(Duration(milliseconds: delayMs));

    if (!mounted) return;
    if (attemptToken != _advanceAttemptToken) return;

    _advancePending = false;
    if (status == 'finished') return;
    if (roundIndex != plannedRound) return;

    _advanceInFlight = true;

    try {
      await RefereeService().advanceRoundOrFinish(widget.debateId);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is Map && details['reason'] == 'ROUND_NOT_ENDED') {
        return;
      }
      if (details is Map && details['reason'] == 'ADVANCE_NOT_PARTICIPANT') {
        return;
      }
    } catch (_) {
      // Молчаливо игнорируем: сервер может отказать (не ваш ход / раунд не закончился)
      // или временно быть недоступным. Повторный вызов сделает retry timer.
    } finally {
      _advanceInFlight = false;
    }
  }

  Future<void> vote1() async {
    final l10n = AppLocalizations.of(context)!;
    if (status == 'finished') return;
    if (!isViewer) return;
    if (hasVotedThisRound) return;
    final callable = _functions.httpsCallable(
      'castVote',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    try {
      await callable.call({
        'debateId': widget.debateId,
        'side': 1,
        'scope': 'round',
      });
      if (!mounted) return;
      setState(() {
        hasVotedThisRound = true;
        votedSideThisRound = 1;
        _voteStatusRoundIndex = roundIndex;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final details = e.details;
      final reason = details is Map ? details['reason']?.toString() ?? '' : '';
      if (reason == 'VOTE_ALREADY_CAST') {
        setState(() {
          hasVotedThisRound = true;
          votedSideThisRound = 0;
          _voteStatusRoundIndex = roundIndex;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapDebateCallableError(
              l10n,
              e,
              fallbackMessage: l10n.alreadyVoted,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.alreadyVoted)),
      );
    }
  }

  Future<void> vote2() async {
    final l10n = AppLocalizations.of(context)!;
    if (status == 'finished') return;
    if (!isViewer) return;
    if (hasVotedThisRound) return;
    final callable = _functions.httpsCallable(
      'castVote',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    try {
      await callable.call({
        'debateId': widget.debateId,
        'side': 2,
        'scope': 'round',
      });
      if (!mounted) return;
      setState(() {
        hasVotedThisRound = true;
        votedSideThisRound = 2;
        _voteStatusRoundIndex = roundIndex;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final details = e.details;
      final reason = details is Map ? details['reason']?.toString() ?? '' : '';
      if (reason == 'VOTE_ALREADY_CAST') {
        setState(() {
          hasVotedThisRound = true;
          votedSideThisRound = 0;
          _voteStatusRoundIndex = roundIndex;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapDebateCallableError(
              l10n,
              e,
              fallbackMessage: l10n.alreadyVoted,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.alreadyVoted)),
      );
    }
  }

  Future<void> sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSendingMessage) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (!isFighter) return;
    if (status == 'finished') return;
    if (!isMyTurn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.notYourTurn)),
      );
      return;
    }

    _bootstrapCurrentUserIdentity();
    final senderName =
        _bestEffortName(FirebaseAuth.instance.currentUser).trim();
    if (senderName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cannotDetectSender)),
      );
      return;
    }

    final callable = _functions.httpsCallable(
      'sendDebateMessage',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    setState(() {
      _isSendingMessage = true;
    });
    try {
      await callable.call({
        'debateId': widget.debateId,
        'text': text,
        'senderName': senderName,
      });
      if (!mounted) return;
      currentUserName = senderName;
      _messageController.clear();
    } on FirebaseFunctionsException catch (e) {
      final retryableCodes = {
        'internal',
        'unavailable',
        'deadline-exceeded',
      };
      if (retryableCodes.contains(e.code)) {
        try {
          await Future.delayed(const Duration(milliseconds: 700));
          await callable.call({
            'debateId': widget.debateId,
            'text': text,
            'senderName': senderName,
          });
          if (!mounted) return;
          currentUserName = senderName;
          _messageController.clear();
          return;
        } catch (_) {}
      }
      final details = e.details;
      final reason = details is Map ? (details['reason'] ?? '').toString() : '';
      if (reason == 'TURN_TIME_EXPIRED' || reason == 'ROUND_NOT_ACTIVE') {
        _attemptAdvanceRoundOrFinish();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(mapDebateCallableError(
          l10n,
          e,
          fallbackMessage: l10n.errorPrefix,
        ))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorPrefix}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  Future<void> _applyPenalty(int seconds) async {
    final l10n = AppLocalizations.of(context)!;
    if (!isFighter) return;
    if (status == 'finished') return;
    final callable = _functions.httpsCallable(
      'applyPenalty',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    try {
      await callable.call({
        'debateId': widget.debateId,
        'seconds': seconds,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${l10n.penaltyAppliedPrefix} -$seconds ${l10n.secondsShort}')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(mapDebateCallableError(
          l10n,
          e,
          fallbackMessage: l10n.penaltyApplyFailed,
        ))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.penaltyApplyFailed)),
      );
    }
  }

  String getTypeLabel() {
    final l10n = AppLocalizations.of(context)!;
    switch (debateType) {
      case 'closed':
        return l10n.closedDebates;
      case 'request':
        return l10n.requestOnlyDebates;
      default:
        return l10n.openDebates;
    }
  }

  Widget _fighterCard(String name, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VerdictStyle.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(Icons.person, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _timerColor(int timeLeft) {
    if (timeLeft <= 5) return const Color(0xFFFF3B30);
    if (timeLeft <= 10) return const Color(0xFFFF6B6B);
    return Colors.white;
  }

  Color _timerPanelColor(bool isDanger, bool pulse) {
    if (!isDanger) return const Color(0xFF151D31);
    return pulse ? const Color(0xFF3A1E27) : const Color(0xFF321B23);
  }

  @override
  void dispose() {
    _roundCountdownTicker?.cancel();
    debateSub?.cancel();
    _advanceAttemptToken++;
    _advancePending = false;
    _messageController.dispose();
    _timeLeftNotifier.dispose();
    _dangerZoneNotifier.dispose();
    _dangerPulseNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayTopic = topic.trim().isEmpty
        ? _safeLocalizedText(l10n.unknownTopic, 'Unknown topic')
        : topic;
    final displayFighter1Name =
        fighter1Name.trim().isEmpty ? l10n.fighterOne : fighter1Name;
    final displayFighter2Name =
        fighter2Name.trim().isEmpty ? l10n.fighterTwo : fighter2Name;
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFFA500),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(displayTopic),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
      ),
      backgroundColor: VerdictStyle.bg,
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Column(
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top + 14),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          children: [
                            Text(
                              getTypeLabel(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  _fighterCard(
                                      displayFighter1Name, Colors.blue),
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 10),
                                    child: Text(
                                      'VS',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFFA500),
                                      ),
                                    ),
                                  ),
                                  _fighterCard(displayFighter2Name, Colors.red),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (status == 'active')
                              ValueListenableBuilder<int>(
                                valueListenable: _timeLeftNotifier,
                                builder: (context, timeLeft, _) {
                                  return ValueListenableBuilder<bool>(
                                    valueListenable: _dangerZoneNotifier,
                                    builder: (context, isDanger, __) {
                                      return ValueListenableBuilder<bool>(
                                        valueListenable: _dangerPulseNotifier,
                                        builder: (context, pulse, ___) {
                                          return AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 350),
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 16),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _timerPanelColor(
                                                  isDanger, pulse),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              border: Border.all(
                                                  color: Colors.white12),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  '${l10n.timeLabel}: $timeLeft',
                                                  style: TextStyle(
                                                    fontSize: 34,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        _timerColor(timeLeft),
                                                  ),
                                                ),
                                                if (timeLeft <= 10)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 8),
                                                    child: Text(
                                                      l10n.timeEnding,
                                                      style: TextStyle(
                                                        color: _timerColor(
                                                            timeLeft),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                        letterSpacing: 1.2,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              )
                            else if (status == 'waiting')
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF151D31),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text(
                                    l10n.waitingOpponent,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                            if (isFighter && status == 'active')
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isMyTurn
                                        ? const Color(0xFF1D2233)
                                        : const Color(0xFF151D31),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text(
                                    '${l10n.roundLabel} $roundIndex/$totalRounds • ${isMyTurn ? l10n.yourTurn : l10n.opponentTurn}',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            if (isFighter && status == 'active')
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 10, 16, 0),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final textWidth = constraints.maxWidth > 180
                                        ? constraints.maxWidth - 160
                                        : constraints.maxWidth;
                                    return Wrap(
                                      runSpacing: 8,
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: textWidth,
                                          child: Text(
                                            pendingPenaltySecondsForMe > 0
                                                ? '${l10n.nextTurnPenaltyPrefix}: -$pendingPenaltySecondsForMe ${l10n.secondsShort}'
                                                : l10n.noNextTurnPenalty,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                        OutlinedButton(
                                          onPressed: isMyTurn
                                              ? () => _applyPenalty(5)
                                              : null,
                                          child: Text('-5${l10n.secondsShort}'),
                                        ),
                                        OutlinedButton(
                                          onPressed: isMyTurn
                                              ? () => _applyPenalty(10)
                                              : null,
                                          child:
                                              Text('-10${l10n.secondsShort}'),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            if (isViewer && status != 'finished')
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  '${l10n.roundLabel} $roundIndex/$totalRounds',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            if (_canAcceptPending) ...[
                              const SizedBox(height: 10),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isAcceptingPending
                                        ? null
                                        : _acceptPendingDebate,
                                    icon: _isAcceptingPending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.black,
                                            ),
                                          )
                                        : const Icon(Icons.how_to_reg),
                                    label: Text(
                                      _isAcceptingPending
                                          ? l10n.accepting
                                          : l10n.acceptChallenge,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFA500),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (isViewer) ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton(
                                    onPressed: (status == 'finished' ||
                                            hasVotedThisRound)
                                        ? null
                                        : vote1,
                                    child: Text('${l10n.voteFor} 1 ($votes1)'),
                                  ),
                                  ElevatedButton(
                                    onPressed: (status == 'finished' ||
                                            hasVotedThisRound)
                                        ? null
                                        : vote2,
                                    child: Text('${l10n.voteFor} 2 ($votes2)'),
                                  ),
                                ],
                              ),
                              if (status != 'finished' && hasVotedThisRound)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    votedSideThisRound == 1
                                        ? '${l10n.alreadyVotedFor} 1'
                                        : (votedSideThisRound == 2
                                            ? '${l10n.alreadyVotedFor} 2'
                                            : l10n.alreadyVotedThisRound),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                            ] else ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1D2233),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text(
                                    l10n.votingOnlyForViewers,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (isViewer)
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151D31),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.remove_red_eye_outlined,
                                        color: Colors.white70),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        l10n.viewerModeHint,
                                        style: const TextStyle(
                                            color: Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: ValueListenableBuilder<int>(
                                valueListenable: _timeLeftNotifier,
                                builder: (context, timeLeft, _) {
                                  final label = status == 'finished'
                                      ? l10n.finishedStatus
                                      : (status == 'waiting'
                                          ? l10n.waitingOpponent
                                          : (isFighter
                                              ? (isMyTurn
                                                  ? l10n.yourTurnUpper
                                                  : l10n.opponentTurnUpper)
                                              : l10n.viewerUpper));
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1D2233),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${l10n.roundLabel} $roundIndex/$totalRounds • $label',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        if (status == 'active')
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFA500)
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              timeLeft <= 0
                                                  ? '00:00'
                                                  : '00:${timeLeft.toString().padLeft(2, '0')}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151D31),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  _termsAreResolved
                                      ? 'Terms trace: creator ${_formatDuration(_termsCreatorDuration)} • $_termsCreatorRounds | accepter ${_formatDuration(_termsAccepterDuration)} • $_termsAccepterRounds | final ${_formatDuration(_termsResolvedDuration)} • $_termsResolvedRounds | $_termsPolicyVersion'
                                      : 'Terms trace: creator ${_formatDuration(_termsCreatorDuration)} • $_termsCreatorRounds | waiting system resolution',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: CustomPaint(
                              painter: ChatPatternPainter(
                                color: Color(0x0AFFFFFF),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: DebateMessagesList(
                              debateId: widget.debateId,
                              fighter1Id: fighter1,
                              showWaitingTurn: isFighter &&
                                  status != 'finished' &&
                                  !isMyTurn,
                              waitingText: l10n.waitingYourTurn,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isFighter && status != 'finished')
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1D2233),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x12000000),
                                        blurRadius: 12,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _messageController,
                                    enabled: isMyTurn,
                                    minLines: 1,
                                    maxLines: 4,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) {
                                      if (isMyTurn && !_isSendingMessage) {
                                        sendMessage();
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: isMyTurn
                                          ? _safeWriteHint(l10n)
                                          : l10n.waitForOpponentTurn,
                                      hintStyle: const TextStyle(
                                          color: Colors.white54),
                                      border: InputBorder.none,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 46,
                                width: 46,
                                child: Material(
                                  color: Colors.transparent,
                                  shape: const CircleBorder(),
                                  child: Opacity(
                                    opacity: (isMyTurn && !_isSendingMessage)
                                        ? 1
                                        : 0.45,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(23),
                                      onTap: (isMyTurn && !_isSendingMessage)
                                          ? sendMessage
                                          : null,
                                      child: Center(
                                        child: Icon(
                                          Icons.send_rounded,
                                          size: 20,
                                          color:
                                              (isMyTurn && !_isSendingMessage)
                                                  ? const Color(0xFFFFA500)
                                                  : Colors.grey,
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
                    if (status == 'finished')
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151D31),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          l10n.battleFinishedGoingToResult,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    ); // end Scaffold
  } // end build
} // end _DebateRoomScreenState

### lib/screens/lobby_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'debate_room_screen.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';

class LobbyScreen extends StatefulWidget {
  final String debateId;
  const LobbyScreen({super.key, required this.debateId});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  static const List<int> _durationOptions = <int>[
    30,
    60,
    90,
    120,
    180,
    300,
    420,
    600,
  ];
  static const List<int> _roundOptions = <int>[1, 3, 5];

  bool _navigated = false;
  bool _showStartedBanner = false;
  bool _isCancelling = false;
  bool _isAccepting = false;
  int? _proposedDurationSeconds;
  int? _proposedTotalRounds;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  int _sanitizeDuration(dynamic value, int fallback) {
    final candidate = value is int ? value : fallback;
    return _durationOptions.contains(candidate) ? candidate : fallback;
  }

  int _sanitizeRounds(dynamic value, int fallback) {
    final candidate = value is int ? value : fallback;
    return _roundOptions.contains(candidate) ? candidate : fallback;
  }

  int _nearestStrict(double raw, List<int> allowed) {
    var best = allowed.first;
    var bestDiff = (raw - best).abs();
    for (final value in allowed.skip(1)) {
      final diff = (raw - value).abs();
      if (diff < bestDiff) {
        best = value;
        bestDiff = diff;
        continue;
      }
      if (diff == bestDiff && value < best) {
        best = value;
      }
    }
    return best;
  }

  Map<String, int> _resolveTerms({
    required int creatorDuration,
    required int creatorRounds,
    required int accepterDuration,
    required int accepterRounds,
  }) {
    final durationMean = (creatorDuration + accepterDuration) / 2;
    final roundsMean = (creatorRounds + accepterRounds) / 2;
    return {
      'durationSeconds': _nearestStrict(durationMean, _durationOptions),
      'totalRounds': _nearestStrict(roundsMean, _roundOptions),
    };
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainderSeconds = seconds % 60;
    return '$minutes:${remainderSeconds.toString().padLeft(2, '0')}';
  }

  String _creationModeLabel(AppLocalizations l10n, String mode) {
    switch (mode) {
      case 'direct_invite':
        return l10n.directInvite;
      case 'public_feed':
      default:
        return l10n.publicFeed;
    }
  }

  String _visibilityModeLabel(AppLocalizations l10n, String mode) {
    switch (mode) {
      case 'request_only':
        return l10n.requestOnly;
      case 'private':
        return l10n.privateMode;
      case 'public':
      default:
        return l10n.publicMode;
    }
  }

  String _languageLabel(AppLocalizations l10n, String code) {
    switch (code) {
      case 'en':
        return l10n.themeLanguageEN;
      case 'ar':
        return l10n.themeLanguageAR;
      case 'zh':
        return l10n.themeLanguageZH;
      case 'es':
        return l10n.themeLanguageES;
      case 'fr':
        return l10n.themeLanguageFR;
      case 'hi':
        return l10n.themeLanguageHI;
      case 'ru':
      default:
        return l10n.themeLanguageRU;
    }
  }

  String _regionLabel(AppLocalizations l10n, String region) {
    switch (region) {
      case 'cis':
        return l10n.regionCis;
      case 'mena':
        return l10n.regionMena;
      case 'europe_africa':
        return l10n.regionEuAf;
      case 'global':
      default:
        return l10n.regionGlobal;
    }
  }

  bool _hasRealOpponentId(String fighter1, String fighter2) {
    final normalized = fighter2.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized == fighter1.trim().toLowerCase()) return false;
    return !const {
      'opponent',
      'invited',
      'fighter',
      'оппонент',
      'приглашен',
      'приглашён',
    }.contains(normalized);
  }

  String _effectiveInvitedUid({
    required String invitedUserId,
    required String creationMode,
    required String fighter1,
    required String fighter2,
    required String opponentId,
  }) {
    if (invitedUserId.isNotEmpty) return invitedUserId;
    if (opponentId.isNotEmpty && opponentId != fighter1) return opponentId;
    if (creationMode == 'direct_invite' &&
        _hasRealOpponentId(fighter1, fighter2)) {
      return fighter2;
    }
    return '';
  }

  Future<void> _cancelDebate() async {
    final l10n = AppLocalizations.of(context)!;
    final callable = _functions.httpsCallable('cancelDebateChallenge');
    final payload = {'debateId': widget.debateId};
    setState(() => _isCancelling = true);
    try {
      await callable.call(payload);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final retryableCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };
      if (!retryableCodes.contains(e.code)) {
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(mapDebateCallableError(
            l10n,
            e,
            fallbackMessage: l10n.cancelChallengeFailed,
          ))),
        );
        return;
      }

      try {
        await Future.delayed(const Duration(milliseconds: 900));
        await callable.call(payload);
        if (!mounted) return;
        Navigator.of(context).pop();
      } on FirebaseFunctionsException catch (retryError) {
        if (!mounted) return;
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(mapDebateCallableError(
            l10n,
            retryError,
            fallbackMessage: l10n.cancelChallengeFailed,
          ))),
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.cancelChallengeFailed)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelChallengeFailed)),
      );
    }
  }

  Future<void> _acceptInvite() async {
    final l10n = AppLocalizations.of(context)!;
    final callable = _functions.httpsCallable('acceptDebateInvite');
    final payload = {
      'debateId': widget.debateId,
      'proposedRoundDurationSeconds': _proposedDurationSeconds,
      'proposedTotalRounds': _proposedTotalRounds,
    };
    setState(() => _isAccepting = true);
    try {
      await callable.call(payload);
      if (!mounted) return;
      setState(() => _isAccepting = false);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final retryableCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };
      if (!retryableCodes.contains(e.code)) {
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mapDebateCallableError(
                l10n,
                e,
                fallbackMessage: l10n.acceptChallengeFailed,
              ),
            ),
          ),
        );
        return;
      }

      try {
        await Future.delayed(const Duration(milliseconds: 900));
        await callable.call(payload);
        if (!mounted) return;
        setState(() => _isAccepting = false);
      } on FirebaseFunctionsException catch (retryError) {
        if (!mounted) return;
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(mapDebateCallableError(
            l10n,
            retryError,
            fallbackMessage: l10n.acceptChallengeFailed,
          ))),
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.acceptChallengeFailed)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAccepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.acceptChallengeFailed)),
      );
    }
  }

  void _triggerStartSequenceIfNeeded() {
    if (_navigated || _showStartedBanner) return;
    setState(() {
      _showStartedBanner = true;
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              DebateRoomScreen(debateId: widget.debateId),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l10n.lobbyWaitingTitle,
          style: const TextStyle(
            color: Color(0xFFFFB74D),
            fontWeight: FontWeight.bold,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0B000000)),
            ),
          ),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('debates')
                .doc(widget.debateId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFB74D)),
                );
              }

              final data = snapshot.data!.data() ?? {};
              final status = data['status'] ?? 'waiting';
              final topic = data['topic'] ?? l10n.loadingTopic;
              final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
              final invitedUserId = (data['invitedUserId'] ?? '').toString();
              final fighter1 = (data['fighter1'] ?? '').toString();
              final fighter2 = (data['fighter2'] ?? '').toString();
              final opponentId = (data['opponentId'] ?? '').toString();
              final creationMode =
                  (data['creationMode'] ?? 'public_feed').toString();
              final visibilityMode =
                  (data['visibilityMode'] ?? 'public').toString();
              final languageCode = (data['languageCode'] ?? 'ru').toString();
              final region = (data['region'] ?? 'global').toString();
              final creatorProposal = data['termsProposalCreator'] is Map
                  ? data['termsProposalCreator'] as Map
                  : const {};
              final creatorDuration = _sanitizeDuration(
                creatorProposal['roundDurationSeconds'],
                _sanitizeDuration(
                    data['roundDurationSeconds'] ?? data['durationSeconds'],
                    180),
              );
              final creatorRounds = _sanitizeRounds(
                creatorProposal['totalRounds'],
                _sanitizeRounds(data['totalRounds'], 3),
              );
              final resolvedTerms = data['termsResolved'] is Map
                  ? data['termsResolved'] as Map
                  : const {};
              final selectedDuration =
                  _sanitizeDuration(_proposedDurationSeconds, creatorDuration);
              final selectedRounds =
                  _sanitizeRounds(_proposedTotalRounds, creatorRounds);
              final accepterProposal = data['termsProposalAccepter'] is Map
                  ? data['termsProposalAccepter'] as Map
                  : const {};
              final accepterDurationSaved = _sanitizeDuration(
                accepterProposal['roundDurationSeconds'],
                selectedDuration,
              );
              final accepterRoundsSaved = _sanitizeRounds(
                accepterProposal['totalRounds'],
                selectedRounds,
              );
              final policyVersion =
                  (data['termsResolverVersion'] ?? 'v1_mean_nearest_strict')
                      .toString();
              final termsResolved =
                  (data['termsResolutionStatus'] ?? '').toString() ==
                      'resolved';
              final resolvedDuration = _sanitizeDuration(
                resolvedTerms['roundDurationSeconds'],
                creatorDuration,
              );
              final resolvedRounds = _sanitizeRounds(
                resolvedTerms['totalRounds'],
                creatorRounds,
              );
              final previewResolved = _resolveTerms(
                creatorDuration: creatorDuration,
                creatorRounds: creatorRounds,
                accepterDuration: selectedDuration,
                accepterRounds: selectedRounds,
              );
              final isDirectInvite = creationMode == 'direct_invite' ||
                  _effectiveInvitedUid(
                    invitedUserId: invitedUserId,
                    creationMode: creationMode,
                    fighter1: fighter1,
                    fighter2: fighter2,
                    opponentId: opponentId,
                  ).isNotEmpty;
              final effectiveInvitedUid = _effectiveInvitedUid(
                invitedUserId: invitedUserId,
                creationMode: creationMode,
                fighter1: fighter1,
                fighter2: fighter2,
                opponentId: opponentId,
              );
              final canAcceptDirectInvite = status == 'waiting' &&
                  effectiveInvitedUid.isNotEmpty &&
                  currentUid == effectiveInvitedUid &&
                  currentUid != fighter1;
              final canAcceptOpenWaiting = status == 'waiting' &&
                  !isDirectInvite &&
                  !_hasRealOpponentId(fighter1, fighter2) &&
                  currentUid.isNotEmpty &&
                  currentUid != fighter1;
              final hasJoinedOpponent = _hasRealOpponentId(fighter1, fighter2);
              final canAcceptInvite =
                  canAcceptDirectInvite || canAcceptOpenWaiting;
              final shouldEnterDebate = status == 'active' ||
                  status == 'live' ||
                  (status == 'waiting' && hasJoinedOpponent);

              if (shouldEnterDebate && !_navigated && !_showStartedBanner) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _triggerStartSequenceIfNeeded();
                });
              }

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: GlassCard(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            topic,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.modesLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${l10n.roundTimeLabel}: ${_formatDuration(creatorDuration)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                Text(
                                  '${l10n.roundsLabel}: $creatorRounds',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                if (termsResolved) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'System final: ${_formatDuration(resolvedDuration)} • $resolvedRounds',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD180),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Trace: creator ${_formatDuration(creatorDuration)} • $creatorRounds | accepter ${_formatDuration(accepterDurationSaved)} • $accepterRoundsSaved | policy $policyVersion',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                Text(
                                  'Creation: ${_creationModeLabel(l10n, creationMode)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                Text(
                                  'Visibility: ${_visibilityModeLabel(l10n, visibilityMode)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                Text(
                                  '${l10n.languageRegionLabel}: ${_languageLabel(l10n, languageCode)} / ${_regionLabel(l10n, region)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                if (canAcceptInvite && !termsResolved) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Your proposal',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _durationOptions
                                        .map(
                                          (v) => ChoiceChip(
                                            selected: selectedDuration == v,
                                            label: Text(_formatDuration(v)),
                                            onSelected:
                                                (_isAccepting || _isCancelling)
                                                    ? null
                                                    : (_) => setState(
                                                          () =>
                                                              _proposedDurationSeconds =
                                                                  v,
                                                        ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _roundOptions
                                        .map(
                                          (v) => ChoiceChip(
                                            selected: selectedRounds == v,
                                            label: Text('$v'),
                                            onSelected:
                                                (_isAccepting || _isCancelling)
                                                    ? null
                                                    : (_) => setState(
                                                          () =>
                                                              _proposedTotalRounds =
                                                                  v,
                                                        ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'System preview: ${_formatDuration(previewResolved['durationSeconds'] ?? selectedDuration)} • ${previewResolved['totalRounds'] ?? selectedRounds}',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD180),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _showStartedBanner
                                ? 'DEBATE STARTED / ДЕБАТЫ НАЧАТЫ'
                                : l10n.waitingOpponent,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _showStartedBanner
                                  ? const Color(0xFF7CFC00)
                                  : const Color(0xFFFFB74D),
                              fontSize: _showStartedBanner ? 22 : 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: _showStartedBanner ? 1.0 : 0.7,
                            ),
                          ),
                          const SizedBox(height: 60),
                          if (!_showStartedBanner)
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 80,
                                    height: 80,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 6,
                                      color: const Color(0xFFFFB74D)
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.search,
                                    size: 40,
                                    color: Color(0xFFFFB74D),
                                  ),
                                ],
                              ),
                            )
                          else
                            const Icon(
                              Icons.bolt,
                              size: 56,
                              color: Color(0xFF7CFC00),
                            ),
                          const SizedBox(height: 40),
                          Text(
                            '${l10n.searchingOpponent}\n${l10n.battleAutoStart}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          if (canAcceptDirectInvite) ...[
                            const SizedBox(height: 16),
                            Text(
                              l10n.invitedToDebate,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 60),
                          if (canAcceptInvite)
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton.icon(
                                icon: _isAccepting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle_outline),
                                label: Text(
                                  _isAccepting
                                      ? l10n.accepting
                                      : l10n.acceptChallenge,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                onPressed: (_isAccepting || _isCancelling)
                                    ? null
                                    : _acceptInvite,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFA500),
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                              ),
                            ),
                          if (canAcceptInvite) const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.cancel),
                              label: _isCancelling
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : Text(l10n.cancelChallenge,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      )),
                              onPressed: _isCancelling ? null : _cancelDebate,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB71C1C),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

### lib/screens/create_debate_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'lobby_screen.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';

class CreateDebateScreen extends StatefulWidget {
  const CreateDebateScreen({super.key});

  @override
  State<CreateDebateScreen> createState() => _CreateDebateScreenState();
}

class _CreateDebateScreenState extends State<CreateDebateScreen> {
  static const List<int> _durationOptions = <int>[
    30,
    60,
    90,
    120,
    180,
    300,
    420,
    600,
  ];

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _invitedUserIdController =
      TextEditingController();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  bool _isLoading = false;
  int _selectedDuration = 180;
  int _selectedRounds = 3;
  String _creationMode = 'public_feed';
  String _visibilityMode = 'public';
  String _languageCode = 'ru';
  String _region = 'global';

  String _sanitizeLanguageCode(String value) {
    const allowed = <String>{'ru', 'en', 'ar'};
    return allowed.contains(value) ? value : 'ru';
  }

  String _sanitizeRegion(String value) {
    const allowed = <String>{'global', 'cis', 'mena', 'europe_africa'};
    return allowed.contains(value) ? value : 'global';
  }

  String _sanitizeCreationMode(String value) {
    const allowed = <String>{'public_feed', 'direct_invite'};
    return allowed.contains(value) ? value : 'public_feed';
  }

  String _sanitizeVisibilityMode(String value) {
    const allowed = <String>{'public', 'request_only', 'private'};
    return allowed.contains(value) ? value : 'public';
  }

  Map<String, dynamic> _buildCreateDebatePayload(String invitedUserId) {
    final creationMode = _sanitizeCreationMode(_creationMode);
    var visibilityMode = _sanitizeVisibilityMode(_visibilityMode);

    // Direct invite must stay private on the backend contract.
    if (creationMode == 'direct_invite') {
      visibilityMode = 'private';
    }

    return {
      'topic': _topicController.text.trim(),
      'durationSeconds': _selectedDuration,
      'totalRounds': _selectedRounds,
      'creationMode': creationMode,
      'visibilityMode': visibilityMode,
      'languageCode': _sanitizeLanguageCode(_languageCode),
      'region': _sanitizeRegion(_region),
      'invitedUserId': invitedUserId,
    };
  }

  String _safeText(String raw, String fallback) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.toUpperCase() == 'NOT_FOUND') {
      return fallback;
    }
    return normalized;
  }

  String? _extractDebateId(dynamic payload) {
    if (payload is String) {
      final value = payload.trim();
      if (value.isNotEmpty) return value;
    }

    if (payload is Map) {
      final direct = (payload['debateId'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;

      final nestedData = payload['data'];
      if (nestedData is Map) {
        final nestedId = (nestedData['debateId'] ?? '').toString().trim();
        if (nestedId.isNotEmpty) return nestedId;
      }

      final result = payload['result'];
      if (result is Map) {
        final resultId = (result['debateId'] ?? '').toString().trim();
        if (resultId.isNotEmpty) return resultId;
      }
    }
    return null;
  }

  String _extractBackendErrorFromPayload(dynamic payload) {
    if (payload is Map) {
      final direct =
          (payload['message'] ?? payload['error'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;

      final reason = payload['reason']?.toString().trim() ?? '';
      if (reason.isNotEmpty) return reason;

      final nested = payload['data'];
      if (nested is Map) {
        final nestedMessage =
            (nested['message'] ?? nested['error'] ?? '').toString().trim();
        if (nestedMessage.isNotEmpty) return nestedMessage;
        final nestedReason = nested['reason']?.toString().trim() ?? '';
        if (nestedReason.isNotEmpty) return nestedReason;
      }
    }
    return '';
  }

  String _resolveCreateErrorMessage(
    AppLocalizations l10n,
    FirebaseFunctionsException error,
  ) {
    final mapped = mapCallableError(
      l10n,
      error,
      fallbackMessage: 'Server error (${error.code})',
    );
    if (mapped.trim().isNotEmpty &&
        mapped.trim().toUpperCase() != 'NOT_FOUND') {
      return mapped;
    }

    final details = error.details;
    final reason =
        details is Map ? (details['reason'] ?? '').toString().trim() : '';
    final backendMessage = (error.message ?? '').trim();
    if (backendMessage.isNotEmpty) return backendMessage;
    if (reason.isNotEmpty) return reason;
    return 'Request failed (${error.code})';
  }

  void _goToLobby(String debateId) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            LobbyScreen(debateId: debateId),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  Future<void> _createDebate(AppLocalizations l10n) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final invitedUserId = _invitedUserIdController.text.trim();
    final payload = _buildCreateDebatePayload(invitedUserId);
    final callable = _functions.httpsCallable(
      'createDebate',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError(
            _safeText(l10n.authRequired, 'Authentication required.'));
      }
      if (payload['creationMode'] == 'direct_invite' && invitedUserId.isEmpty) {
        throw StateError(_safeText(l10n.directInviteNeedsOpponent,
            'Direct invite requires opponent ID.'));
      }
      if (payload['visibilityMode'] == 'private' && invitedUserId.isEmpty) {
        throw StateError(_safeText(
            l10n.privateNeedsOpponent, 'Private debate requires opponent ID.'));
      }

      debugPrint('createDebate request payload: $payload');
      final res = await callable.call(payload);
      debugPrint('createDebate raw response: ${res.data}');
      final debateId = _extractDebateId(res.data);
      if (debateId == null) {
        final payloadError = _extractBackendErrorFromPayload(res.data);
        final noIdMessage = _safeText(
          l10n.serverNoDebateId,
          'Backend did not return debateId.',
        );
        throw StateError(
          payloadError.isNotEmpty
              ? payloadError
              : '$noIdMessage Response: ${res.data}',
        );
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      _goToLobby(debateId);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'createDebate FirebaseFunctionsException: code=${e.code}, message=${e.message}, details=${e.details}');
      if (!mounted) return;
      final retryableCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };

      if (!retryableCodes.contains(e.code)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_resolveCreateErrorMessage(l10n, e)),
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      try {
        await Future.delayed(const Duration(milliseconds: 900));
        final retry = await callable.call(payload);
        debugPrint('createDebate retry raw response: ${retry.data}');
        final debateId = _extractDebateId(retry.data);
        if (debateId == null) {
          final payloadError = _extractBackendErrorFromPayload(retry.data);
          final noIdMessage = _safeText(
            l10n.serverNoDebateId,
            'Backend did not return debateId.',
          );
          throw StateError(
            payloadError.isNotEmpty
                ? payloadError
                : '$noIdMessage Response: ${retry.data}',
          );
        }
        if (!mounted) return;
        setState(() => _isLoading = false);
        _goToLobby(debateId);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_resolveCreateErrorMessage(l10n, e)),
          ),
        );
        setState(() => _isLoading = false);
      }
    } on StateError catch (e) {
      if (!mounted) return;
      final text = e.message.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(text.isNotEmpty ? text : 'Create debate failed.')),
      );
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      final prefix = _safeText(l10n.errorPrefix, 'Error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$prefix: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    _invitedUserIdController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0x662A3147),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Color(0xFFFFA500), width: 2),
      ),
    );
  }

  String _durationChipLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainderSeconds = seconds % 60;
    final ss = remainderSeconds.toString().padLeft(2, '0');
    return '$minutes:$ss';
  }

  Widget _buildChoiceChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFA500) : const Color(0xFF1D2233),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? const Color(0xFFFFA500) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: VerdictStyle.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          l10n.createBattleTitle,
          style: const TextStyle(
            color: Color(0xFFFFA500),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0B000000)),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: GlassCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.debateTopicLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _topicController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: _inputDecoration(l10n.enterTopic),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? l10n.enterTopicValidation
                            : null,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.roundTimeLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _durationOptions
                            .map(
                              (seconds) => _buildChoiceChip(
                                selected: _selectedDuration == seconds,
                                label: _durationChipLabel(seconds),
                                onTap: () =>
                                    setState(() => _selectedDuration = seconds),
                              ),
                            )
                            .toList(),
                      ),
                      Text(
                        l10n.roundsLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            selected: _selectedRounds == 1,
                            label: l10n.oneRound,
                            onTap: () => setState(() => _selectedRounds = 1),
                          ),
                          _buildChoiceChip(
                            selected: _selectedRounds == 3,
                            label: l10n.threeRounds,
                            onTap: () => setState(() => _selectedRounds = 3),
                          ),
                          _buildChoiceChip(
                            selected: _selectedRounds == 5,
                            label: l10n.fiveRounds,
                            onTap: () => setState(() => _selectedRounds = 5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.modesLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            selected: _creationMode == 'public_feed',
                            label: l10n.publicFeed,
                            onTap: () => setState(() {
                              _creationMode = 'public_feed';
                              if (_visibilityMode == 'private') {
                                _visibilityMode = 'request_only';
                              }
                            }),
                          ),
                          _buildChoiceChip(
                            selected: _creationMode == 'direct_invite',
                            label: l10n.directInvite,
                            onTap: () =>
                                setState(() => _creationMode = 'direct_invite'),
                          ),
                          _buildChoiceChip(
                            selected: _visibilityMode == 'public',
                            label: l10n.publicMode,
                            onTap: () =>
                                setState(() => _visibilityMode = 'public'),
                          ),
                          _buildChoiceChip(
                            selected: _visibilityMode == 'request_only',
                            label: l10n.requestOnly,
                            onTap: () => setState(
                                () => _visibilityMode = 'request_only'),
                          ),
                          _buildChoiceChip(
                            selected: _visibilityMode == 'private',
                            label: l10n.privateMode,
                            onTap: () => setState(() {
                              _visibilityMode = 'private';
                              _creationMode = 'direct_invite';
                            }),
                          ),
                        ],
                      ),
                      if (_creationMode == 'direct_invite' ||
                          _visibilityMode == 'private') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _invitedUserIdController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                          decoration: _inputDecoration(l10n.opponentId),
                          validator: (v) {
                            if (_creationMode != 'direct_invite') return null;
                            if (v == null || v.trim().isEmpty) {
                              return l10n.enterOpponentId;
                            }
                            return null;
                          },
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        l10n.languageRegionLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            selected: _languageCode == 'ru',
                            label: 'RU',
                            onTap: () => setState(() => _languageCode = 'ru'),
                          ),
                          _buildChoiceChip(
                            selected: _languageCode == 'en',
                            label: 'EN',
                            onTap: () => setState(() => _languageCode = 'en'),
                          ),
                          _buildChoiceChip(
                            selected: _languageCode == 'ar',
                            label: 'AR',
                            onTap: () => setState(() => _languageCode = 'ar'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'global',
                            label: l10n.regionGlobal,
                            onTap: () => setState(() => _region = 'global'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'cis',
                            label: l10n.regionCis,
                            onTap: () => setState(() => _region = 'cis'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'mena',
                            label: l10n.regionMena,
                            onTap: () => setState(() => _region = 'mena'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'europe_africa',
                            label: l10n.regionEuAf,
                            onTap: () =>
                                setState(() => _region = 'europe_africa'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed:
                              _isLoading ? null : () => _createDebate(l10n),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFA500),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2),
                                )
                              : Text(
                                  l10n.publishChallenge,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1),
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
      ),
    );
  }
}

### functions/src/index.ts

import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getCoreRuntimeFlags } from './core/runtime_flags';
import { incrementCoreMetric, logCoreEvent } from './core/telemetry';
import {
  assertCanAdvanceOrFinish,
  assertCanCancelDebate,
  assertCanCastVote,
  assertCanCreateDebate,
  assertCanFinishDebate,
  assertCanSendMessage,
  assertTransitionInvariants,
  evaluateAcceptGuard,
} from './domain/debate/guards';

admin.initializeApp();

const db = admin.firestore();
const LEGACY_NAME_PLACEHOLDERS = new Set([
  'guest',
  'google user',
  'fighter',
  'fighter 1',
  'fighter 2',
  'opponent',
  'invited',
  'user',
  'гость',
  'боец',
  'боец 1',
  'боец 2',
  'оппонент',
  'вы',
]);
const LEGACY_OPPONENT_ID_PLACEHOLDERS = new Set([
  'opponent',
  'invited',
  'fighter',
  'оппонент',
  'приглашен',
  'приглашён',
]);
const ALLOWED_DURATIONS = [30, 60, 90, 120, 180, 300, 420, 600] as const;
const ALLOWED_ROUNDS = [1, 3, 5] as const;
const TERMS_POLICY_VERSION = 'v1_mean_nearest_strict';
const MAX_MIGRATION_EMERGENCY_TTL_MS = 24 * 60 * 60 * 1000;
const CANONICAL_DEBATE_STATUSES = ['waiting', 'active', 'finished'] as const;

function asString(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function normalizeName(value: unknown): string {
  const s = asString(value).trim();
  if (!s) return '';
  if (LEGACY_NAME_PLACEHOLDERS.has(s.toLowerCase())) return '';
  return s;
}

function normalizeTopic(value: unknown): string {
  const s = asString(value).trim();
  if (!s) return '';
  const lower = s.toLowerCase();
  if (lower === 'новая дуэль' || lower === 'new duel') return '';
  return s;
}

function deriveNeutralUserName(params: {
  profileName: unknown;
  tokenName: unknown;
  tokenEmail: unknown;
  uid: string;
}): string {
  const profileName = normalizeName(params.profileName);
  if (profileName) return profileName;

  const tokenName = normalizeName(params.tokenName);
  if (tokenName) return tokenName;

  const email = asString(params.tokenEmail).trim();
  if (email) {
    const localPart = normalizeName(email.split('@')[0]);
    if (localPart) return localPart;
  }

  return params.uid;
}

function hasRealOpponentId(fighter1: string, fighter2: string): boolean {
  const f2 = fighter2.trim();
  if (!f2) return false;
  if (f2 === fighter1.trim()) return false;
  return !LEGACY_OPPONENT_ID_PLACEHOLDERS.has(f2.toLowerCase());
}

async function requireAdminOrFounder(request: {
  auth?: { uid?: string; token?: Record<string, unknown> };
}): Promise<void> {
  const uid = request.auth?.uid ?? '';
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.', {
      reason: 'MIGRATION_AUTH_REQUIRED',
    });
  }

  if (request.auth?.token?.admin === true) {
    return;
  }

  const userSnap = await db.collection('users').doc(uid).get();
  const rank = asString(userSnap.data()?.rank).trim();
  if (rank === 'GRANDMASTER') {
    return;
  }

  const accessSnap = await db.collection('admin_runtime').doc('migration_access').get();
  const accessData = accessSnap.data() ?? {};
  const enabled = accessData['enabled'] === true;
  const allowedUids = Array.isArray(accessData['allowedUids'])
    ? accessData['allowedUids'].map((v: unknown) => asString(v)).filter((v: string) => !!v)
    : [];
  const expiresAtRaw = accessData['expiresAt'];
  const expiresAt = expiresAtRaw instanceof admin.firestore.Timestamp
    ? expiresAtRaw
    : null;
  const nowMs = Date.now();
  const expiresAtMs = expiresAt?.toMillis() ?? 0;
  const hasValidExpiry = expiresAtMs > nowMs;
  const withinTtlWindow = hasValidExpiry && expiresAtMs <= nowMs + MAX_MIGRATION_EMERGENCY_TTL_MS;
  const emergencyAllowed =
    enabled &&
    withinTtlWindow &&
    allowedUids.includes(uid);
  if (emergencyAllowed) {
    await db.collection('admin_migration_access_audit').add({
      uid,
      email: asString(request.auth?.token?.email).trim(),
      reason: asString(accessData['reason']).trim(),
      expiresAt,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  throw new HttpsError('permission-denied', 'Only admins can run this operation.', {
    reason: 'MIGRATION_ADMIN_REQUIRED',
  });
}

function clampText(text: string): string {
  const t = text.trim();
  if (t.length > 2000) return t.slice(0, 2000);
  return t;
}

function asInt(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

function sanitizeAllowedInt(
  value: unknown,
  allowed: readonly number[],
  fallback: number,
): number {
  const candidate = asInt(value, fallback);
  return allowed.includes(candidate) ? candidate : fallback;
}

function nearestAllowedStrict(
  raw: number,
  allowed: readonly number[],
): number {
  let best = allowed[0];
  let bestDiff = Math.abs(raw - best);
  for (let i = 1; i < allowed.length; i++) {
    const current = allowed[i];
    const diff = Math.abs(raw - current);
    if (diff < bestDiff) {
      best = current;
      bestDiff = diff;
      continue;
    }
    // Tie-break toward stricter setting (lower value).
    if (diff === bestDiff && current < best) {
      best = current;
    }
  }
  return best;
}

function resolveTerms(params: {
  creatorDurationSeconds: number;
  creatorTotalRounds: number;
  accepterDurationSeconds: number;
  accepterTotalRounds: number;
}): {
  durationSeconds: number;
  totalRounds: number;
} {
  const durationMean =
    (params.creatorDurationSeconds + params.accepterDurationSeconds) / 2;
  const roundsMean =
    (params.creatorTotalRounds + params.accepterTotalRounds) / 2;
  return {
    durationSeconds: nearestAllowedStrict(durationMean, ALLOWED_DURATIONS),
    totalRounds: nearestAllowedStrict(roundsMean, ALLOWED_ROUNDS),
  };
}

function readCreatorTermsProposal(data: Record<string, unknown>): {
  durationSeconds: number;
  totalRounds: number;
} {
  const legacyDuration = sanitizeAllowedInt(
    data.roundDurationSeconds ?? data.durationSeconds,
    ALLOWED_DURATIONS,
    180,
  );
  const legacyRounds = sanitizeAllowedInt(data.totalRounds, ALLOWED_ROUNDS, 3);

  const proposal = data.termsProposalCreator;
  if (!proposal || typeof proposal !== 'object') {
    return {
      durationSeconds: legacyDuration,
      totalRounds: legacyRounds,
    };
  }

  const proposalMap = proposal as Record<string, unknown>;
  return {
    durationSeconds: sanitizeAllowedInt(
      proposalMap.roundDurationSeconds,
      ALLOWED_DURATIONS,
      legacyDuration,
    ),
    totalRounds: sanitizeAllowedInt(
      proposalMap.totalRounds,
      ALLOWED_ROUNDS,
      legacyRounds,
    ),
  };
}

function deriveDebateStyle(params: {
  totalDebates: number;
  wins: number;
  draws: number;
  reputation: number;
  viewerScore: number;
}): string {
  const total = params.totalDebates > 0 ? params.totalDebates : 1;
  const winScore = params.wins + params.draws * 0.5;
  const winRate = winScore / total;

  if (params.reputation <= -10) return 'Volatile';
  if (params.viewerScore >= 40 && params.reputation >= 15) return 'Charismatic';
  if (winRate >= 0.65 && params.reputation >= 5) return 'Dominant';
  if (winRate < 0.4 && params.reputation >= 0) return 'Underdog';
  if (params.reputation >= 10) return 'Composed';
  return 'Balanced';
}

function invitedIds(data: Record<string, unknown>): string[] {
  const raw = data.invitedUserIds;
  if (!Array.isArray(raw)) return [];
  return raw.map((v) => asString(v)).filter((v) => !!v);
}

function normalizeDebateStatus(
  value: unknown,
  fallback: (typeof CANONICAL_DEBATE_STATUSES)[number] = 'waiting',
): (typeof CANONICAL_DEBATE_STATUSES)[number] {
  const raw = asString(value);
  if (!raw) return fallback;
  if (raw === 'live') return 'active';
  if (raw === 'waiting' || raw === 'active' || raw === 'finished') return raw;
  return fallback;
}

function readRoundIndex(data: Record<string, unknown>, fallback = 1): number {
  if (typeof data.roundIndex === 'number') return data.roundIndex;
  if (typeof data.currentRound === 'number') return data.currentRound;
  if (typeof data.round === 'number') return data.round;
  return fallback;
}

function readRoundDurationSeconds(data: Record<string, unknown>, fallback = 60): number {
  if (typeof data.roundDurationSeconds === 'number') return data.roundDurationSeconds;
  if (typeof data.durationSeconds === 'number') return data.durationSeconds;
  if (typeof data.timeSeconds === 'number') return data.timeSeconds;
  return fallback;
}

function hasLegacyWritePayload(data: unknown): boolean {
  if (!data || typeof data !== 'object') return false;
  const map = data as Record<string, unknown>;
  const rawStatus = asString(map['status']).toLowerCase();
  return (
    Object.prototype.hasOwnProperty.call(map, 'timeSeconds')
    || Object.prototype.hasOwnProperty.call(map, 'durationSec')
    || Object.prototype.hasOwnProperty.call(map, 'round')
    || Object.prototype.hasOwnProperty.call(map, 'currentRound')
    || Object.prototype.hasOwnProperty.call(map, 'fighter1')
    || Object.prototype.hasOwnProperty.call(map, 'fighter2')
    || Object.prototype.hasOwnProperty.call(map, 'creatorId')
    || Object.prototype.hasOwnProperty.call(map, 'opponentId')
    || rawStatus === 'live'
  );
}

function approvedIds(data: Record<string, unknown>): string[] {
  const raw = data.accessApprovedUserIds;
  if (!Array.isArray(raw)) return [];
  return raw.map((v) => asString(v)).filter((v) => !!v);
}

function canAccessRequestOnly(uid: string, data: Record<string, unknown>): boolean {
  if (!uid) return false;
  return isDebateParticipant(uid, data) || approvedIds(data).includes(uid);
}

function isDebateParticipant(uid: string, data: Record<string, unknown>): boolean {
  if (!uid) return false;
  const creatorId = asString(data.creatorId);
  const opponentId = asString(data.opponentId);
  const fighter1 = asString(data.fighter1) || creatorId;
  const fighter2 = asString(data.fighter2) || opponentId;
  const creationMode = asString(data.creationMode) || 'public_feed';
  const invitedUserId = asString(data.invitedUserId);
  const reservedInviteUid = invitedUserId
    || (creationMode === 'direct_invite' ? (opponentId || fighter2) : '');
  const invitedUserIds = invitedIds(data);
  return uid === fighter1
    || uid === fighter2
    || uid === creatorId
    || uid === opponentId
    || uid === invitedUserId
    || uid === reservedInviteUid
    || invitedUserIds.includes(uid);
}

function canUserReadDebate(uid: string, data: Record<string, unknown>): boolean {
  const visibilityMode = asString(data.visibilityMode) || 'public';
  const creationMode = asString(data.creationMode) || 'public_feed';
  const participant = isDebateParticipant(uid, data);

  if (visibilityMode === 'private') return participant;
  if (visibilityMode === 'request_only') return canAccessRequestOnly(uid, data);
  if (creationMode === 'direct_invite' && !participant) return false;
  return true;
}

/** Дебат идёт (сообщения/голоса): в данных встречаются и `live`, и `active`. */
function isDebatePlayableStatus(status: string): boolean {
  return normalizeDebateStatus(status, 'waiting') === 'active';
}

/**
 * Reads debates/{id}/votes subcollection once (non-transactionally) and returns
 * total side-1 and side-2 vote counts across all vote keys (round_N and debate).
 * Used only at debate finish time — not during live voting.
 */
async function aggregateVoteCounts(
  debateRef: admin.firestore.DocumentReference,
): Promise<{ votes1: number; votes2: number }> {
  const snap = await debateRef.collection('votes').get();
  let votes1 = 0;
  let votes2 = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    for (const [key, val] of Object.entries(data)) {
      if (key === 'uid' || key === 'updatedAt') continue;
      if (val === 1) votes1++;
      else if (val === 2) votes2++;
    }
  }
  return { votes1, votes2 };
}

export const createDebate = onCall(async (request) => {
  const coreFlags = await getCoreRuntimeFlags(db);
  if (!coreFlags.legacyWriteEnabled && hasLegacyWritePayload(request.data)) {
    await incrementCoreMetric(db, 'legacy.write.blocked.count', {
      action: 'createDebate',
    });
    throw new HttpsError('failed-precondition', 'Legacy write payload is disabled.', {
      reason: 'LEGACY_WRITE_DISABLED',
    });
  }

  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'CREATE_AUTH_REQUIRED',
    });
  }

  const topic = clampText(asString(request.data?.topic));
  const durationSeconds = asInt(request.data?.durationSeconds, 180);
  const totalRounds = asInt(request.data?.totalRounds, 3);
  const creationMode = asString(request.data?.creationMode) || 'public_feed';
  const visibilityMode = asString(request.data?.visibilityMode) || 'public';
  const languageCode = asString(request.data?.languageCode) || 'ru';
  const region = asString(request.data?.region) || 'global';
  const invitedUserId = asString(request.data?.invitedUserId);

  const allowedCreationModes = ['public_feed', 'direct_invite'] as const;
  const allowedVisibilityModes = ['public', 'request_only', 'private'] as const;
  const allowedLanguages = ['ru', 'en', 'ar'] as const;
  const allowedRegions = ['global', 'cis', 'mena', 'europe_africa'] as const;

  assertCanCreateDebate({
    uid,
    topic,
    durationSeconds,
    totalRounds,
    creationMode,
    visibilityMode,
    languageCode,
    region,
    invitedUserId,
    allowedCreationModes,
    allowedVisibilityModes,
    allowedLanguages,
    allowedRegions,
    allowedDurations: ALLOWED_DURATIONS,
    allowedRounds: ALLOWED_ROUNDS,
  });

  const userDoc = await db.collection('users').doc(uid).get();
  const fighter1Name = deriveNeutralUserName({
    profileName: userDoc.data()?.name,
    tokenName: request.auth?.token?.name,
    tokenEmail: request.auth?.token?.email,
    uid,
  });

  const debateRef = db.collection('debates').doc();
  const accessApprovedUserIds = invitedUserId ? [uid, invitedUserId] : [uid];
  await debateRef.set({
    topic,
    creatorId: uid,
    fighter1: uid,
    fighter1Name,
    fighter2: invitedUserId || '',
    fighter2Name: '',
    invitedUserId: invitedUserId || '',
    status: 'waiting',
    durationSeconds,
    roundDurationSeconds: durationSeconds,
    totalRounds,
    termsProposalCreator: {
      uid,
      roundDurationSeconds: durationSeconds,
      totalRounds,
      submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    termsResolved: {
      roundDurationSeconds: durationSeconds,
      totalRounds,
      policyVersion: TERMS_POLICY_VERSION,
      resolutionMode: 'initial_creator_defaults',
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    termsResolutionStatus: 'pending_opponent',
    termsResolverVersion: TERMS_POLICY_VERSION,
    roundIndex: 1,
    creationMode,
    visibilityMode,
    languageCode,
    region,
    viewerCount: 0,
    votes1: 0,
    votes2: 0,
    accessRequests: [],
    accessApprovedUserIds,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    schemaVersion: 2,
    migrationState: 'pre_backfill',
    normalizerVersion: 'v2_runtime_flags',
    transitionPolicyVersion: coreFlags.strictTransitionsEnabled ? 'strict_v1' : 'compat_v1',
  });

  await incrementCoreMetric(db, 'action.create.accepted.count');
  await logCoreEvent(db, 'debate.created', {
    debateId: debateRef.id,
    actorUid: uid,
    status: 'waiting',
    schemaVersion: 2,
  });

  return {
    debateId: debateRef.id,
  };
});

export const acceptDebateInvite = onCall(async (request) => {
  const coreFlags = await getCoreRuntimeFlags(db);
  if (!coreFlags.legacyWriteEnabled && hasLegacyWritePayload(request.data)) {
    await incrementCoreMetric(db, 'legacy.write.blocked.count', {
      action: 'acceptDebateInvite',
    });
    throw new HttpsError('failed-precondition', 'Legacy write payload is disabled.', {
      reason: 'LEGACY_WRITE_DISABLED',
    });
  }

  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'ACCEPT_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const requestedDurationSeconds = request.data?.proposedRoundDurationSeconds;
  const requestedTotalRounds = request.data?.proposedTotalRounds;
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ACCEPT_DEBATE_ID_REQUIRED',
    });
  }

  if (
    requestedDurationSeconds !== undefined
    && !(ALLOWED_DURATIONS as readonly number[]).includes(asInt(requestedDurationSeconds, -1))
  ) {
    throw new HttpsError('invalid-argument', 'Некорректная длительность раунда в предложении оппонента.', {
      reason: 'ACCEPT_PROPOSAL_DURATION_INVALID',
    });
  }
  if (
    requestedTotalRounds !== undefined
    && !(ALLOWED_ROUNDS as readonly number[]).includes(asInt(requestedTotalRounds, -1))
  ) {
    throw new HttpsError('invalid-argument', 'Некорректное число раундов в предложении оппонента.', {
      reason: 'ACCEPT_PROPOSAL_ROUNDS_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const termsAuditRef = db.collection('admin_terms_resolution_audit').doc();
  let acceptNoop = false;

  await db.runTransaction(async (tx) => {
    const debateSnap = await tx.get(debateRef);
    if (!debateSnap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'ACCEPT_NOT_FOUND',
      });
    }

    const debate = debateSnap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'waiting');

    const fighter1 = asString(debate.fighter1) || asString(debate.creatorId);
    const fighter2 = asString(debate.fighter2) || asString(debate.opponentId);
    const invitedUserId = asString(debate.invitedUserId);
    const opponentId = asString(debate.opponentId);
    const creationMode = asString(debate.creationMode) || 'public_feed';
    const acceptGuard = evaluateAcceptGuard({
      uid,
      status,
      fighter1,
      fighter2,
      invitedUserId,
      opponentId,
      creationMode,
      strictTransitionsEnabled: coreFlags.strictTransitionsEnabled,
    });
    if (acceptGuard.noop) {
      acceptNoop = true;
      return;
    }

    const userRef = db.collection('users').doc(uid);
    const userSnap = await tx.get(userRef);
    const fighter2Name = deriveNeutralUserName({
      profileName: userSnap.data()?.name,
      tokenName: request.auth?.token?.name,
      tokenEmail: request.auth?.token?.email,
      uid,
    });

    const creatorProposal = readCreatorTermsProposal(debate);
    const accepterDurationSeconds = sanitizeAllowedInt(
      requestedDurationSeconds,
      ALLOWED_DURATIONS,
      creatorProposal.durationSeconds,
    );
    const accepterTotalRounds = sanitizeAllowedInt(
      requestedTotalRounds,
      ALLOWED_ROUNDS,
      creatorProposal.totalRounds,
    );
    const resolved = resolveTerms({
      creatorDurationSeconds: creatorProposal.durationSeconds,
      creatorTotalRounds: creatorProposal.totalRounds,
      accepterDurationSeconds,
      accepterTotalRounds,
    });
    const durationChanged = resolved.durationSeconds !== creatorProposal.durationSeconds
      || resolved.durationSeconds !== accepterDurationSeconds;
    const roundsChanged = resolved.totalRounds !== creatorProposal.totalRounds
      || resolved.totalRounds !== accepterTotalRounds;
    const effective = Math.max(resolved.durationSeconds, 5);

    const acceptPatch: Record<string, unknown> = {
      fighter1,
      fighter2: uid,
      opponentId: uid,
      fighter2Name,
      status: 'active',
      durationSeconds: resolved.durationSeconds,
      roundDurationSeconds: resolved.durationSeconds,
      totalRounds: resolved.totalRounds,
      termsProposalCreator: {
        uid: asString(debate.creatorId) || fighter1,
        roundDurationSeconds: creatorProposal.durationSeconds,
        totalRounds: creatorProposal.totalRounds,
      },
      termsProposalAccepter: {
        uid,
        roundDurationSeconds: accepterDurationSeconds,
        totalRounds: accepterTotalRounds,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      termsResolved: {
        roundDurationSeconds: resolved.durationSeconds,
        totalRounds: resolved.totalRounds,
        policyVersion: TERMS_POLICY_VERSION,
        resolutionMode: 'system_reconciled',
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      termsResolutionStatus: 'resolved',
      termsResolverVersion: TERMS_POLICY_VERSION,
      isRoundActive: true,
      roundIndex: readRoundIndex(debate, 1),
      activeSpeakerId: asString(debate.activeSpeakerId) || fighter1,
      roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      accessApprovedUserIds: admin.firestore.FieldValue.arrayUnion(uid),
      accessRequests: admin.firestore.FieldValue.arrayRemove(uid),
      schemaVersion: 2,
      migrationState: 'pre_backfill',
      normalizerVersion: 'v2_runtime_flags',
      transitionPolicyVersion: coreFlags.strictTransitionsEnabled ? 'strict_v1' : 'compat_v1',
    };

    if (coreFlags.strictTransitionsEnabled) {
      const nextDebate = {
        ...debate,
        ...acceptPatch,
      } as Record<string, unknown>;
      assertTransitionInvariants(debate as Record<string, unknown>, nextDebate);
    }

    tx.update(debateRef, acceptPatch);

    tx.set(termsAuditRef, {
      debateId,
      statusBeforeAccept: status,
      policyVersion: TERMS_POLICY_VERSION,
      resolutionMode: 'system_reconciled',
      creatorUid: asString(debate.creatorId) || fighter1,
      accepterUid: uid,
      creatorProposal: {
        roundDurationSeconds: creatorProposal.durationSeconds,
        totalRounds: creatorProposal.totalRounds,
      },
      accepterProposal: {
        roundDurationSeconds: accepterDurationSeconds,
        totalRounds: accepterTotalRounds,
      },
      resolved: {
        roundDurationSeconds: resolved.durationSeconds,
        totalRounds: resolved.totalRounds,
      },
      changed: {
        duration: durationChanged,
        rounds: roundsChanged,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  if (acceptNoop) {
    await incrementCoreMetric(db, 'action.accept.noop.count');
    await logCoreEvent(db, 'debate.accept.noop', {
      debateId,
      actorUid: uid,
      status: 'active',
    });
    return {
      ok: true,
      policyVersion: TERMS_POLICY_VERSION,
      noop: true,
    };
  }

  await incrementCoreMetric(db, 'action.accept.accepted.count');
  await logCoreEvent(db, 'debate.accepted', {
    debateId,
    actorUid: uid,
    nextStatus: 'active',
    schemaVersion: 2,
    strictTransitions: coreFlags.strictTransitionsEnabled,
  });

  return {
    ok: true,
    policyVersion: TERMS_POLICY_VERSION,
  };
});

export const requestDebateAccess = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'ACCESS_REQUEST_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ACCESS_REQUEST_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'ACCESS_REQUEST_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    if (asString(debate.visibilityMode) !== 'request_only') {
      throw new HttpsError('failed-precondition', 'Этот дебат не требует заявки на доступ.', {
        reason: 'ACCESS_REQUEST_NOT_REQUIRED',
      });
    }
    if (asString(debate.status) === 'finished') {
      throw new HttpsError('failed-precondition', 'Дебат завершён.', {
        reason: 'ACCESS_REQUEST_DEBATE_FINISHED',
      });
    }
    if (canAccessRequestOnly(uid, debate)) {
      throw new HttpsError('failed-precondition', 'У вас уже есть доступ к дебату.', {
        reason: 'ACCESS_REQUEST_ALREADY_GRANTED',
      });
    }

    const requests = Array.isArray(debate.accessRequests)
      ? debate.accessRequests.map((v: unknown) => asString(v)).filter((v: string) => !!v)
      : [];
    if (requests.includes(uid)) {
      throw new HttpsError('already-exists', 'Запрос уже отправлен.', {
        reason: 'ACCESS_REQUEST_ALREADY_SENT',
      });
    }

    tx.update(debateRef, {
      accessRequests: admin.firestore.FieldValue.arrayUnion(uid),
    });
  });

  return { ok: true };
});

export const cancelDebateChallenge = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'CANCEL_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'CANCEL_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'CANCEL_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = asString(debate.status) || 'waiting';
    assertCanCancelDebate({
      uid,
      creatorId: asString(debate.creatorId),
      status,
    });

    tx.delete(debateRef);
  });

  return { ok: true };
});

export const adminDeleteDebate = onCall(async (request) => {
  await requireAdminOrFounder(request);

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ADMIN_DELETE_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const debateSnap = await debateRef.get();
  if (!debateSnap.exists) {
    throw new HttpsError('not-found', 'Дебат не найден.', {
      reason: 'ADMIN_DELETE_NOT_FOUND',
    });
  }

  while (true) {
    const messagesSnap = await debateRef.collection('messages').limit(200).get();
    if (messagesSnap.empty) {
      break;
    }

    const batch = db.batch();
    for (const doc of messagesSnap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  await debateRef.delete();

  await logCoreEvent(db, 'debate.admin_deleted', {
    debateId,
    actorUid: request.auth?.uid ?? '',
  });

  return { ok: true };
});

export const moderateAccessRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'MODERATE_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const targetUid = asString(request.data?.targetUid);
  const action = asString(request.data?.action);

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'MODERATE_DEBATE_ID_REQUIRED',
    });
  }
  if (!targetUid) {
    throw new HttpsError('invalid-argument', 'targetUid обязателен.', {
      reason: 'MODERATE_TARGET_UID_REQUIRED',
    });
  }
  if (action !== 'approve' && action !== 'reject') {
    throw new HttpsError('invalid-argument', 'action должен быть approve или reject.', {
      reason: 'MODERATE_ACTION_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'MODERATE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    if (asString(debate.visibilityMode) !== 'request_only') {
      throw new HttpsError('failed-precondition', 'Модерация заявок доступна только для request_only дебатов.', {
        reason: 'MODERATE_NOT_REQUEST_ONLY',
      });
    }
    if (asString(debate.creatorId) !== uid) {
      throw new HttpsError('permission-denied', 'Только создатель может модерировать заявки.', {
        reason: 'MODERATE_NOT_CREATOR',
      });
    }
    if (asString(debate.status) === 'finished') {
      throw new HttpsError('failed-precondition', 'Дебат завершён.', {
        reason: 'MODERATE_DEBATE_FINISHED',
      });
    }

    const requests = Array.isArray(debate.accessRequests)
      ? debate.accessRequests.map((v: unknown) => asString(v)).filter((v: string) => !!v)
      : [];

    if (!requests.includes(targetUid)) {
      throw new HttpsError('failed-precondition', 'Заявка пользователя не найдена.', {
        reason: 'MODERATE_REQUEST_NOT_FOUND',
      });
    }

    if (action === 'approve') {
      tx.update(debateRef, {
        accessApprovedUserIds: admin.firestore.FieldValue.arrayUnion(targetUid),
        accessRequests: admin.firestore.FieldValue.arrayRemove(targetUid),
      });
      return;
    }

    tx.update(debateRef, {
      accessRequests: admin.firestore.FieldValue.arrayRemove(targetUid),
    });
  });

  return { ok: true };
});

export const sendDebateMessage = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'MESSAGE_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const rawText = asString(request.data?.text);
  const senderName = asString(request.data?.senderName);
  const text = clampText(rawText);

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'MESSAGE_DEBATE_ID_REQUIRED',
    });
  }
  if (!text) {
    throw new HttpsError('invalid-argument', 'Текст сообщения пуст.', {
      reason: 'MESSAGE_TEXT_EMPTY',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const messageRef = debateRef.collection('messages').doc();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'MESSAGE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'active');
    const guard = assertCanSendMessage({
      uid,
      debate: debate as Record<string, unknown>,
      hasReadAccess: canUserReadDebate(uid, debate),
      status,
      isPlayableStatus: isDebatePlayableStatus(status),
    });
    const roundIndex = guard.roundIndex;

    tx.set(messageRef, {
      text,
      senderId: uid,
      senderName: normalizeName(senderName) || uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      roundIndex,
    });
  });

  return { ok: true, messageId: messageRef.id };
});

export const applyPenalty = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'PENALTY_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const seconds = asInt(request.data?.seconds, 0);

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'PENALTY_DEBATE_ID_REQUIRED',
    });
  }
  if (seconds <= 0 || seconds > 30) {
    throw new HttpsError('invalid-argument', 'seconds должен быть 1..30.', {
      reason: 'PENALTY_SECONDS_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'PENALTY_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'active');
    if (status === 'finished') {
      throw new HttpsError('failed-precondition', 'Дебат завершён.', {
        reason: 'PENALTY_DEBATE_FINISHED',
      });
    }
    if (!isDebatePlayableStatus(status)) {
      throw new HttpsError('failed-precondition', 'Штраф недоступен в текущем статусе дебата.', {
        reason: 'PENALTY_DEBATE_NOT_PLAYABLE',
      });
    }

    const isRoundActive = typeof debate.isRoundActive === 'boolean' ? debate.isRoundActive : true;
    if (!isRoundActive) {
      throw new HttpsError('failed-precondition', 'Раунд не активен.', {
        reason: 'ROUND_NOT_ACTIVE',
      });
    }

    const fighter1 = asString(debate.fighter1) || asString(debate.creatorId);
    const fighter2 = asString(debate.fighter2) || asString(debate.opponentId);
    if (uid !== fighter1 && uid !== fighter2) {
      throw new HttpsError('permission-denied', 'Только бойцы могут назначать штраф.', {
        reason: 'TURN_NOT_FIGHTER',
      });
    }

    const activeSpeakerId = asString(debate.activeSpeakerId);
    if (!activeSpeakerId) {
      throw new HttpsError('failed-precondition', 'Сейчас невозможно применить штраф: не назначен активный спикер.', {
        reason: 'TURN_NOT_ASSIGNED',
      });
    }
    if (uid !== activeSpeakerId) {
      throw new HttpsError('failed-precondition', 'Штраф может назначать только активный спикер.', {
        reason: 'TURN_NOT_ACTIVE_SPEAKER',
      });
    }

    const targetId = uid === fighter1 ? fighter2 : fighter1;
    if (!targetId) {
      throw new HttpsError('failed-precondition', 'Нет оппонента.', {
        reason: 'PENALTY_NO_OPPONENT',
      });
    }

    // Простейший rate-limit: не чаще 1 раза в 10 секунд на дебат.
    const lastPenaltyAt = debate.lastPenaltyAt;
    if (lastPenaltyAt && typeof lastPenaltyAt.toDate === 'function') {
      const lastMs = (lastPenaltyAt.toDate() as Date).getTime();
      if (Date.now() - lastMs < 10_000) {
        throw new HttpsError('resource-exhausted', 'Штраф можно ставить не чаще чем раз в 10 секунд.', {
          reason: 'PENALTY_RATE_LIMIT',
        });
      }
    }

    const roundDurationSeconds = readRoundDurationSeconds(debate, 60);
    const minTurnSeconds = 5;

    const roundEndsAt = debate.roundEndsAt;

    // Если штрафуем того, кто СЕЙЧАС говорит — режем roundEndsAt сразу.
    if (activeSpeakerId && activeSpeakerId === targetId && roundEndsAt && typeof roundEndsAt.toDate === 'function') {
      const endMs = (roundEndsAt.toDate() as Date).getTime();
      const nowMs = Date.now();

      const proposedEnd = endMs - seconds * 1000;
      const minEnd = nowMs + minTurnSeconds * 1000;
      const newEnd = Math.max(proposedEnd, minEnd);

      tx.update(debateRef, {
        roundEndsAt: admin.firestore.Timestamp.fromMillis(newEnd),
        lastPenaltyAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPenaltyBy: uid,
        lastPenaltySeconds: seconds,
      });

      return;
    }

    // Иначе — копим pendingPenalty для оппонента и применим при старте его хода.
    const pending = (typeof debate.pendingPenalty === 'object' && debate.pendingPenalty) ? debate.pendingPenalty as Record<string, unknown> : {};
    const currentPending = asInt(pending[targetId], 0);
    const nextPending = Math.min(currentPending + seconds, roundDurationSeconds - minTurnSeconds);

    tx.update(debateRef, {
      pendingPenalty: {
        ...pending,
        [targetId]: nextPending,
      },
      lastPenaltyAt: admin.firestore.FieldValue.serverTimestamp(),
      lastPenaltyBy: uid,
      lastPenaltySeconds: seconds,
    });
  });

  return { ok: true };
});

export const castVote = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'VOTE_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const side = asInt(request.data?.side, 0);
  const scope = asString(request.data?.scope) || 'round';

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'VOTE_DEBATE_ID_REQUIRED',
    });
  }
  if (side !== 1 && side !== 2) {
    throw new HttpsError('invalid-argument', 'side должен быть 1 или 2.', {
      reason: 'VOTE_SIDE_INVALID',
    });
  }
  if (scope !== 'round' && scope !== 'debate') {
    throw new HttpsError('invalid-argument', 'scope должен быть round или debate.', {
      reason: 'VOTE_SCOPE_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'VOTE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'active');
    const guard = assertCanCastVote({
      uid,
      debate: debate as Record<string, unknown>,
      hasReadAccess: canUserReadDebate(uid, debate),
      status,
      isPlayableStatus: isDebatePlayableStatus(status),
    });
    const roundIndex = guard.roundIndex;
    const voteKey = scope === 'debate' ? `debate` : `round_${roundIndex}`;
    const voteRef = debateRef.collection('votes').doc(uid);

    const voteSnap = await tx.get(voteRef);
    const existing = voteSnap.exists ? (voteSnap.data() ?? {}) : {};
    const existingForKey = existing[voteKey];
    if (existingForKey === 1 || existingForKey === 2) {
      throw new HttpsError('already-exists', 'Вы уже голосовали.', {
        reason: 'VOTE_ALREADY_CAST',
      });
    }

    // Записываем голос в карту (one doc per user).
    tx.set(voteRef, {
      uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      [voteKey]: side,
    }, { merge: true });


  });
  return { ok: true };
});

export const getMyVoteStatus = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'VOTE_STATUS_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const scope = asString(request.data?.scope) || 'round';

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'VOTE_STATUS_DEBATE_ID_REQUIRED',
    });
  }
  if (scope !== 'round' && scope !== 'debate') {
    throw new HttpsError('invalid-argument', 'scope должен быть round или debate.', {
      reason: 'VOTE_STATUS_SCOPE_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const voteRef = debateRef.collection('votes').doc(uid);

  const [debateSnap, voteSnap] = await Promise.all([
    debateRef.get(),
    voteRef.get(),
  ]);

  if (!debateSnap.exists) {
    throw new HttpsError('not-found', 'Дебат не найден.', {
      reason: 'VOTE_STATUS_NOT_FOUND',
    });
  }
  const debate = debateSnap.data() ?? {};
  if (!canUserReadDebate(uid, debate)) {
    throw new HttpsError('permission-denied', 'Доступ к дебату ограничен.', {
      reason: 'VOTE_STATUS_ACCESS_DENIED',
    });
  }

  const roundIndex = readRoundIndex(debate, 1);

  const voteKey = scope === 'debate' ? 'debate' : `round_${roundIndex}`;

  const voteData = voteSnap.exists ? (voteSnap.data() ?? {}) : {};
  const sideRaw = voteData[voteKey];
  const side = (sideRaw === 1 || sideRaw === 2) ? sideRaw : 0;

  return {
    ok: true,
    roundIndex,
    scope,
    hasVoted: side === 1 || side === 2,
    side,
  };
});

export const advanceRoundOrFinish = onCall(async (request) => {
  const coreFlags = await getCoreRuntimeFlags(db);
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'ADVANCE_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ADVANCE_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'ADVANCE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    assertCanAdvanceOrFinish({
      uid,
      debate: debate as Record<string, unknown>,
    });
    const status = normalizeDebateStatus(debate.status, 'active');
    if (status === 'finished') return;

    const updateWithTransitionCheck = (patch: Record<string, unknown>): void => {
      if (coreFlags.strictTransitionsEnabled) {
        const nextDebate = {
          ...debate,
          ...patch,
        } as Record<string, unknown>;
        assertTransitionInvariants(debate as Record<string, unknown>, nextDebate);
      }
      tx.update(debateRef, patch);
    };

    const roundDurationSeconds = readRoundDurationSeconds(debate, 60);

    const roundEndsAt = debate.roundEndsAt;
    if (!roundEndsAt || typeof roundEndsAt.toDate !== 'function') {
      // Если поля нет (старые дебаты) — создаём endAt и выходим.
      updateWithTransitionCheck({
        isRoundActive: true,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + roundDurationSeconds * 1000),
        activeSpeakerId: asString(debate.activeSpeakerId) || asString(debate.fighter1),
        roundIndex: readRoundIndex(debate, 1),
      });
      return;
    }

    const nowMs = Date.now();
    const endMs = (roundEndsAt.toDate() as Date).getTime();
    // Не бросаем ошибку: клиенты/таймеры часто опрашивают advance — no-op без шума в логах.
    if (nowMs < endMs) {
      return;
    }

    const totalRounds = (typeof debate.totalRounds === 'number' ? debate.totalRounds : 3);
    const currentRound = readRoundIndex(debate, 1);

    const fighter1 = asString(debate.fighter1);
    const fighter2 = asString(debate.fighter2);
    const activeSpeakerId = asString(debate.activeSpeakerId) || fighter1;

    // SOLO / INVALID OPPONENT GUARD:
    // Если fighter2 не задан или это плейсхолдер (например, "Оппонент"),
    // не переключаем ход на несуществующего пользователя — иначе чат “умирает”.
    const hasRealOpponent = hasRealOpponentId(fighter1, fighter2);
    if (!hasRealOpponent) {
      const effective = Math.max(roundDurationSeconds, 5);
      updateWithTransitionCheck({
        isRoundActive: true,
        activeSpeakerId: fighter1,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
      });
      return;
    }

    const pending = (typeof debate.pendingPenalty === 'object' && debate.pendingPenalty) ? debate.pendingPenalty as Record<string, unknown> : {};
    const takePenalty = (who: string): number => {
      if (!who) return 0;
      const p = asInt(pending[who], 0);
      return p > 0 ? p : 0;
    };

    // TURN SWITCH LOGIC (по таймеру):
    // - если говорил fighter1 -> переключаем на fighter2 (тот же раунд)
    // - если говорил fighter2 -> следующий раунд, снова fighter1
    if (activeSpeakerId === fighter1 && fighter2) {
      const penalty = takePenalty(fighter2);
      const effective = Math.max(roundDurationSeconds - penalty, 5);
      updateWithTransitionCheck({
        isRoundActive: true,
        activeSpeakerId: fighter2,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
        pendingPenalty: {
          ...pending,
          [fighter2]: 0,
        },
      });
      return;
    }

    // Закончился ход fighter2 -> следующий раунд или финиш
    if (currentRound < totalRounds) {
      const nextRound = currentRound + 1;
      const penalty = takePenalty(fighter1);
      const effective = Math.max(roundDurationSeconds - penalty, 5);
      updateWithTransitionCheck({
        isRoundActive: true,
        roundIndex: nextRound,
        activeSpeakerId: fighter1,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
        pendingPenalty: {
          ...pending,
          [fighter1]: 0,
        },
      });
      return;
    }

    assertCanFinishDebate({
      debate: debate as Record<string, unknown>,
      status,
    });

    // Aggregate final vote counts from subcollection — debate doc counters are no longer
    // maintained during voting, so we compute them once at finish time.
    const finalCounts = await aggregateVoteCounts(debateRef);
    const votes1 = finalCounts.votes1;
    const votes2 = finalCounts.votes2;
    const winner = votes1 > votes2 ? 'fighter1' : (votes2 > votes1 ? 'fighter2' : 'draw');

    updateWithTransitionCheck({
      isRoundActive: false,
      status: 'finished',
      winner,
      votes1,
      votes2,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

// 1) Инициализация дебата: выставляем roundEndsAt сразу на сервере.
export const initDebateOnCreate = onDocumentCreated(
  'debates/{debateId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() ?? {};

    const status = normalizeDebateStatus(data.status, 'active');
    if (status === 'finished') return;

    const fighter1 = asString(data.fighter1);
    const fighter2 = asString(data.fighter2);
    const hasOpponent = hasRealOpponentId(fighter1, fighter2);
    const roundDurationSeconds = readRoundDurationSeconds(data, 60);

    const patch: Record<string, unknown> = {};

    if (!data.activeSpeakerId) patch.activeSpeakerId = fighter1;
    if (typeof data.isRoundActive !== 'boolean') patch.isRoundActive = true;
    if (typeof data.roundIndex !== 'number') patch.roundIndex = readRoundIndex(data, 1);
    if (status === 'waiting' && hasOpponent) patch.status = 'active';

    // Только если ещё не выставлено.
    if (!data.roundEndsAt) {
      patch.roundEndsAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + roundDurationSeconds * 1000,
      );
    }

    // Подготовим pendingPenalty под обоих бойцов (если оба есть).
    if (!data.pendingPenalty) {
      const pending: Record<string, number> = {};
      if (fighter1) pending[fighter1] = 0;
      if (fighter2) pending[fighter2] = 0;
      if (Object.keys(pending).length > 0) patch.pendingPenalty = pending;
    }

    if (Object.keys(patch).length > 0) {
      await snap.ref.update(patch);
    }
  },
);

// 2) Авто-рефери: периодически переключаем ход/раунд, если время вышло.
export const autoAdvanceLiveDebates = onSchedule(
  { schedule: 'every 1 minutes' },
  async () => {
    const now = admin.firestore.Timestamp.now();

    // Берём только активные дебаты, где roundEndsAt уже прошёл.
    // (Если понадобится — добавим индекс позже.)
    const q = await db
      .collection('debates')
      .where('status', 'in', ['live', 'active'])
      .where('roundEndsAt', '<=', now)
      .limit(50)
      .get();

    if (q.empty) return;

    // По одному, чтобы не ловить contention; функция advanceRoundOrFinish уже транзакционная.
    for (const doc of q.docs) {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        const debate = snap.data() ?? {};
        const status = normalizeDebateStatus(debate.status, 'active');
        if (status === 'finished') return;

        // Эмулируем логику advanceRoundOrFinish, но без auth.
        const roundDurationSeconds = readRoundDurationSeconds(debate, 60);

        const roundEndsAt = debate.roundEndsAt;
        if (!roundEndsAt || typeof roundEndsAt.toDate !== 'function') {
          tx.update(doc.ref, {
            isRoundActive: true,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + roundDurationSeconds * 1000),
            activeSpeakerId: asString(debate.activeSpeakerId) || asString(debate.fighter1),
            roundIndex: readRoundIndex(debate, 1),
          });
          return;
        }

        const endMs = (roundEndsAt.toDate() as Date).getTime();
        if (Date.now() < endMs) return;

        const totalRounds = (typeof debate.totalRounds === 'number' ? debate.totalRounds : 3);
        const currentRound = readRoundIndex(debate, 1);

        const fighter1 = asString(debate.fighter1);
        const fighter2 = asString(debate.fighter2);
        const activeSpeakerId = asString(debate.activeSpeakerId) || fighter1;

        const hasRealOpponent = hasRealOpponentId(fighter1, fighter2);
        if (!hasRealOpponent) {
          tx.update(doc.ref, {
            isRoundActive: true,
            activeSpeakerId: fighter1,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + Math.max(roundDurationSeconds, 5) * 1000),
          });
          return;
        }

        const pending = (typeof debate.pendingPenalty === 'object' && debate.pendingPenalty) ? debate.pendingPenalty as Record<string, unknown> : {};
        const takePenalty = (who: string): number => {
          if (!who) return 0;
          const p = asInt(pending[who], 0);
          return p > 0 ? p : 0;
        };

        if (activeSpeakerId === fighter1 && fighter2) {
          const penalty = takePenalty(fighter2);
          const effective = Math.max(roundDurationSeconds - penalty, 5);
          tx.update(doc.ref, {
            isRoundActive: true,
            activeSpeakerId: fighter2,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
            pendingPenalty: {
              ...pending,
              [fighter2]: 0,
            },
          });
          return;
        }

        if (currentRound < totalRounds) {
          const nextRound = currentRound + 1;
          const penalty = takePenalty(fighter1);
          const effective = Math.max(roundDurationSeconds - penalty, 5);
          tx.update(doc.ref, {
            isRoundActive: true,
            roundIndex: nextRound,
            activeSpeakerId: fighter1,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
            pendingPenalty: {
              ...pending,
              [fighter1]: 0,
            },
          });
          return;
        }

        // Aggregate final vote counts from subcollection (same pattern as callable path).
        const finalCounts = await aggregateVoteCounts(doc.ref);
        const votes1 = finalCounts.votes1;
        const votes2 = finalCounts.votes2;
        const winner = votes1 > votes2 ? 'fighter1' : (votes2 > votes1 ? 'fighter2' : 'draw');

        tx.update(doc.ref, {
          isRoundActive: false,
          status: 'finished',
          winner,
          votes1,
          votes2,
          finishedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }
  },
);

export const applyDebateResultToProfiles = onDocumentUpdated(
  'debates/{debateId}',
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};

    const beforeStatus = asString(before.status) || '';
    const afterStatus = asString(after.status) || '';
    if (beforeStatus === 'finished' || afterStatus !== 'finished') {
      return;
    }

    const debateRef = event.data?.after.ref;
    if (!debateRef) return;

    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(debateRef);
      if (!freshSnap.exists) return;

      const debate = freshSnap.data() ?? {};
      if (asString(debate.status) !== 'finished') return;
      if (debate.profileStatsApplied === true) return;

      const fighter1 = asString(debate.fighter1);
      const fighter2 = asString(debate.fighter2);
      const winner = asString(debate.winner);
      const votes1 = asInt(debate.votes1, 0);
      const votes2 = asInt(debate.votes2, 0);

      // Mark processed even for invalid/solo debates to avoid endless retries.
      if (!fighter1 || !hasRealOpponentId(fighter1, fighter2)) {
        tx.update(debateRef, {
          profileStatsApplied: true,
          profileStatsAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const f1Ref = db.collection('users').doc(fighter1);
      const f2Ref = db.collection('users').doc(fighter2);
      const [f1Snap, f2Snap] = await Promise.all([
        tx.get(f1Ref),
        tx.get(f2Ref),
      ]);
      const f1Data = f1Snap.data() ?? {};
      const f2Data = f2Snap.data() ?? {};

      const f1Won = winner === 'fighter1';
      const f2Won = winner === 'fighter2';
      const isDraw = winner === 'draw';

      const f1RatingDelta = f1Won ? 12 : (f2Won ? -8 : 2);
      const f2RatingDelta = f2Won ? 12 : (f1Won ? -8 : 2);
      const f1ReputationDelta = f1Won ? 2 : (f2Won ? -1 : 1);
      const f2ReputationDelta = f2Won ? 2 : (f1Won ? -1 : 1);

      // Viewer score is tied to vote performance and kept bounded by moderate increments.
      const f1ViewerDelta = isDraw
        ? 0.5
        : (f1Won ? Math.max(1, votes1 - votes2 + 1) : -1);
      const f2ViewerDelta = isDraw
        ? 0.5
        : (f2Won ? Math.max(1, votes2 - votes1 + 1) : -1);

      const f1NextTotalDebates = asInt(f1Data.totalDebates, 0) + 1;
      const f1NextWins = asInt(f1Data.wins, 0) + (f1Won ? 1 : 0);
      const f1NextDraws = asInt(f1Data.draws, 0) + (isDraw ? 1 : 0);
      const f1NextReputation = asInt(f1Data.reputation, 0) + f1ReputationDelta;
      const f1NextViewerScore = asInt(f1Data.viewerScore, 0) + f1ViewerDelta;
      const f1NextStyle = deriveDebateStyle({
        totalDebates: f1NextTotalDebates,
        wins: f1NextWins,
        draws: f1NextDraws,
        reputation: f1NextReputation,
        viewerScore: f1NextViewerScore,
      });

      const f2NextTotalDebates = asInt(f2Data.totalDebates, 0) + 1;
      const f2NextWins = asInt(f2Data.wins, 0) + (f2Won ? 1 : 0);
      const f2NextDraws = asInt(f2Data.draws, 0) + (isDraw ? 1 : 0);
      const f2NextReputation = asInt(f2Data.reputation, 0) + f2ReputationDelta;
      const f2NextViewerScore = asInt(f2Data.viewerScore, 0) + f2ViewerDelta;
      const f2NextStyle = deriveDebateStyle({
        totalDebates: f2NextTotalDebates,
        wins: f2NextWins,
        draws: f2NextDraws,
        reputation: f2NextReputation,
        viewerScore: f2NextViewerScore,
      });

      tx.set(f1Ref, {
        totalDebates: admin.firestore.FieldValue.increment(1),
        wins: admin.firestore.FieldValue.increment(f1Won ? 1 : 0),
        losses: admin.firestore.FieldValue.increment(f2Won ? 1 : 0),
        draws: admin.firestore.FieldValue.increment(isDraw ? 1 : 0),
        rating: admin.firestore.FieldValue.increment(f1RatingDelta),
        reputation: admin.firestore.FieldValue.increment(f1ReputationDelta),
        viewerScore: admin.firestore.FieldValue.increment(f1ViewerDelta),
        debateStyle: f1NextStyle,
        lastDebateAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      tx.set(f2Ref, {
        totalDebates: admin.firestore.FieldValue.increment(1),
        wins: admin.firestore.FieldValue.increment(f2Won ? 1 : 0),
        losses: admin.firestore.FieldValue.increment(f1Won ? 1 : 0),
        draws: admin.firestore.FieldValue.increment(isDraw ? 1 : 0),
        rating: admin.firestore.FieldValue.increment(f2RatingDelta),
        reputation: admin.firestore.FieldValue.increment(f2ReputationDelta),
        viewerScore: admin.firestore.FieldValue.increment(f2ViewerDelta),
        debateStyle: f2NextStyle,
        lastDebateAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      tx.update(debateRef, {
        profileStatsApplied: true,
        profileStatsAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  },
);

export const migrateLegacyNamePlaceholders = onCall(async (request) => {
  await requireAdminOrFounder(request);

  const dryRun = request.data?.dryRun !== false;
  const batchSize = Math.min(
    Math.max(asInt(request.data?.batchSize, 500), 50),
    1000,
  );
  const maxDocsPerCollection = Math.min(
    Math.max(asInt(request.data?.maxDocsPerCollection, 500), 1),
    50000,
  );

  const summary = {
    dryRun,
    maxDocsPerCollection,
    users: { scanned: 0, updated: 0 },
    debates: { scanned: 0, updated: 0 },
    worldMessages: { scanned: 0, updated: 0 },
    debateMessages: { scanned: 0, updated: 0 },
  };
  const actorUid = request.auth?.uid ?? '';
  const actorEmail = asString(request.auth?.token?.email).trim();
  const lockRef = db.collection('admin_runtime').doc('migration_lock');
  const runRef = db.collection('admin_migration_runs').doc();

  await db.runTransaction(async (tx) => {
    const lockSnap = await tx.get(lockRef);
    const lockData = lockSnap.data() ?? {};
    if (lockData['inProgress'] === true) {
      throw new HttpsError('failed-precondition', 'Migration is already running.', {
        reason: 'MIGRATION_ALREADY_RUNNING',
      });
    }

    tx.set(lockRef, {
      inProgress: true,
      actorUid,
      actorEmail,
      dryRun,
      batchSize,
      maxDocsPerCollection,
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(runRef, {
      actorUid,
      actorEmail,
      dryRun,
      batchSize,
      maxDocsPerCollection,
      users: summary.users,
      debates: summary.debates,
      worldMessages: summary.worldMessages,
      debateMessages: summary.debateMessages,
      status: 'in_progress',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: null,
    });
  });

  try {
    async function processCollection(
      buildQuery: (
        lastDoc?: admin.firestore.QueryDocumentSnapshot,
      ) => admin.firestore.Query,
      onDoc: (
        doc: admin.firestore.QueryDocumentSnapshot,
      ) => Promise<void>,
      onScanned: () => void,
    ): Promise<void> {
      let scanned = 0;
      let lastDoc: admin.firestore.QueryDocumentSnapshot | undefined;

      while (scanned < maxDocsPerCollection) {
        const remaining = maxDocsPerCollection - scanned;
        const queryLimit = Math.min(batchSize, remaining);
        const snap = await buildQuery(lastDoc).limit(queryLimit).get();
        if (snap.empty) {
          break;
        }

        for (const doc of snap.docs) {
          await onDoc(doc);
          onScanned();
          scanned += 1;
        }

        lastDoc = snap.docs[snap.docs.length - 1];
        if (snap.docs.length < queryLimit) {
          break;
        }
      }
    }

    await processCollection(
      (lastDoc) => {
        let q = db.collection('users').orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const patch: Record<string, unknown> = {};

        const normalizedName = normalizeName(data.name);
        if (asString(data.name).trim() && !normalizedName) {
          patch.name = '';
        }

        const normalizedDisplayName = normalizeName(data.displayName);
        if (asString(data.displayName).trim() && !normalizedDisplayName) {
          patch.displayName = '';
        }

        if (Object.keys(patch).length > 0) {
          summary.users.updated += 1;
          if (!dryRun) {
            await doc.ref.update(patch);
          }
        }
      },
      () => {
        summary.users.scanned += 1;
      },
    );

    await processCollection(
      (lastDoc) => {
        let q = db.collection('debates').orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const patch: Record<string, unknown> = {};

        const topic = normalizeTopic(data.topic);
        if (asString(data.topic).trim() && !topic) {
          patch.topic = '';
        }

        const fighter1Name = normalizeName(data.fighter1Name);
        if (asString(data.fighter1Name).trim() && !fighter1Name) {
          patch.fighter1Name = '';
        }

        const fighter2Name = normalizeName(data.fighter2Name);
        if (asString(data.fighter2Name).trim() && !fighter2Name) {
          patch.fighter2Name = '';
        }

        const fighter2 = asString(data.fighter2).trim();
        if (fighter2 && LEGACY_OPPONENT_ID_PLACEHOLDERS.has(fighter2.toLowerCase())) {
          patch.fighter2 = '';
        }

        if (Object.keys(patch).length > 0) {
          summary.debates.updated += 1;
          if (!dryRun) {
            await doc.ref.update(patch);
          }
        }
      },
      () => {
        summary.debates.scanned += 1;
      },
    );

    await processCollection(
      (lastDoc) => {
        let q = db.collection('world_messages').orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const normalizedSenderName = normalizeName(data.senderName);
        if (asString(data.senderName).trim() && !normalizedSenderName) {
          summary.worldMessages.updated += 1;
          if (!dryRun) {
            await doc.ref.update({ senderName: '' });
          }
        }
      },
      () => {
        summary.worldMessages.scanned += 1;
      },
    );

    await processCollection(
      (lastDoc) => {
        let q = db
          .collectionGroup('messages')
          .orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const normalizedSenderName = normalizeName(data.senderName);
        if (asString(data.senderName).trim() && !normalizedSenderName) {
          summary.debateMessages.updated += 1;
          if (!dryRun) {
            await doc.ref.update({ senderName: '' });
          }
        }
      },
      () => {
        summary.debateMessages.scanned += 1;
      },
    );

    await runRef.set({
      users: summary.users,
      debates: summary.debates,
      worldMessages: summary.worldMessages,
      debateMessages: summary.debateMessages,
      status: 'completed',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
      ok: true,
      runId: runRef.id,
      ...summary,
    };
  } catch (error) {
    await runRef.set({
      users: summary.users,
      debates: summary.debates,
      worldMessages: summary.worldMessages,
      debateMessages: summary.debateMessages,
      status: 'failed',
      errorMessage: error instanceof Error ? error.message : String(error),
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    throw error;
  } finally {
    await lockRef.set({
      inProgress: false,
      lastActorUid: actorUid,
      lastActorEmail: actorEmail,
      lastDryRun: dryRun,
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
});


### lib/services/referee_service.dart

import 'package:cloud_functions/cloud_functions.dart';

class RefereeService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> advanceRoundOrFinish(String debateId) async {
    await _callAdvanceRoundOrFinish(debateId);
  }

  Future<void> finishDebate(String debateId) async {
    await _callAdvanceRoundOrFinish(debateId);
  }

  Future<void> _callAdvanceRoundOrFinish(String debateId) async {
    final callable = _functions.httpsCallable('advanceRoundOrFinish');
    await callable.call({'debateId': debateId});
  }
}

### lib/services/debate_service.dart

Файл не найден.

### lib/models/debate_model.dart

Файл не найден.

## 3) Структура папки lib/

lib/app.dart
lib/firebase_options.dart
lib/l10n/app_ar.arb
lib/l10n/app_en.arb
lib/l10n/app_es.arb
lib/l10n/app_fr.arb
lib/l10n/app_hi.arb
lib/l10n/app_localizations.dart
lib/l10n/app_localizations_ar.dart
lib/l10n/app_localizations_en.dart
lib/l10n/app_localizations_es.dart
lib/l10n/app_localizations_fr.dart
lib/l10n/app_localizations_hi.dart
lib/l10n/app_localizations_ru.dart
lib/l10n/app_localizations_zh.dart
lib/l10n/app_ru.arb
lib/l10n/app_zh.arb
lib/main.dart
lib/models/debate.dart
lib/models/debate_history_item.dart
lib/models/debate_lobby.dart
lib/painters/chat_pattern_painter.dart
lib/screens/auth_screen.dart
lib/screens/create_debate_screen.dart
lib/screens/debate_room_screen.dart
lib/screens/home_screen.dart
lib/screens/lobby_screen.dart
lib/screens/profile_history_screen.dart
lib/screens/profile_screen.dart
lib/screens/public_profile_screen.dart
lib/screens/result_screen.dart
lib/screens/settings_screen.dart
lib/screens/splash_screen.dart
lib/screens/verdict.code-workspace
lib/screens/welcome_screen.dart
lib/screens/world_chat_screen.dart
lib/services/admin_service.dart
lib/services/app_locale_controller.dart
lib/services/auth_service.dart
lib/services/debate_alert_service.dart
lib/services/debate_timer_service.dart
lib/services/lobby_service.dart
lib/services/notification_service.dart
lib/services/rank_service.dart
lib/services/referee_service.dart
lib/services/stats_service.dart
lib/services/winner_service.dart
lib/utils/debate_error_mapper.dart
lib/utils/name_utils.dart
lib/utils/style_utils.dart
lib/widgets/debate_messages_list.dart
lib/widgets/player_card.dart
lib/widgets/reaction_button.dart
lib/widgets/timer_widget.dart

## 4) pubspec.yaml

name: verdict
description: "A new Flutter project."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2
  cupertino_icons: ^1.0.2
  vibration: ^2.0.0
  # Библиотеки для Firebase и Google входа
  firebase_core: ^4.0.0
  firebase_auth: ^6.0.0
  cloud_firestore: ^6.0.0
  cloud_functions: ^6.0.0
  google_sign_in: ^6.2.1
  
  # Иконки для интерфейса
  font_awesome_flutter: ^10.12.0
  firebase_storage: ^13.0.0
  image_picker: ^1.2.1
  shared_preferences: ^2.3.2
  flutter_displaymode: ^0.6.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  # Инструмент для создания иконок приложения
  flutter_launcher_icons: "^0.13.1"

# Настройка иконок приложения (твое золотое V)
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/logo.png"
  adaptive_icon_background: "#000000"
  adaptive_icon_foreground: "assets/logo.png"

flutter:
  uses-material-design: true
  generate: true
  # Регистрация папки с картинками
  assets:
    - assets/logo.png
## 5) WARNING / TODO, связанные с debate flow

lib/screens/debate_room_screen.dart:46
// TODO: Implement vote status refresh logic if needed.
