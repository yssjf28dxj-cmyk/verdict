import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/debate.dart';
import '../painters/chat_pattern_painter.dart';
import '../widgets/debate_messages_list.dart';
import '../widgets/debate_input_bar.dart';
import '../services/media_upload_service.dart';
import '../services/referee_service.dart';
import '../services/debate_alert_service.dart';
import '../services/sound_service.dart';
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

class _DebateRoomScreenState extends State<DebateRoomScreen>
    with WidgetsBindingObserver {
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
  // Must mirror UPLOAD_GRACE_MS in functions/src/index.ts.
  // Keeps the client from triggering advance during the server-side grace window.
  static const int _uploadGraceMs = 7000;
  static const double _snapThresholdPx = 20;

  void _refreshMyVoteStatus() {
    setState(() {
      hasVotedThisRound = false;
      votedSideThisRound = 0;
    });
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
  // ignore: unused_field
  bool _termsAreResolved = false;

  bool isLoading = true;
  bool movedToResult = false;
  bool _accessDeniedHandled = false;

  // ─── MEDIA STATE ──────────────────────────────────────────
  bool _isRecording = false;
  bool _isUploadingMedia = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordingPath;
  DateTime? _recordingStartTime;

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
  bool _graceDelayActive = false;
  bool _isSendingMessage = false;
  bool _isYieldingTurn = false;
  int _advanceAttemptToken = 0;
  int _lastAdvanceRoundAttempt = -1;
  String _lastAdvanceSpeakerAttempt = '';
  DateTime? _lastAdvanceAttemptAt;
  int _lastDangerHapticSecond = -1;
  String _lastBellCueKey = '';
  bool _headerCollapsed = false;
  // _isTyping removed — now owned by DebateInputBar._NormalInputBar
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
    WidgetsBinding.instance.addObserver(this);
    _timeLeftNotifier = ValueNotifier<int>(60);
    _dangerZoneNotifier = ValueNotifier<bool>(false);
    _dangerPulseNotifier = ValueNotifier<bool>(false);
    _bootstrapCurrentUserIdentity();
    _startRoundCountdownTicker();
    _loadDebate();
  }

  /// Releases the microphone when the app is backgrounded or interrupted
  /// by an incoming call. Prevents mic lock and silent crash on iOS/Android.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isRecording) {
        debugPrint('[Voice] App backgrounded — cancelling active recording.');
        _cancelRecording();
      }
    }
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

      if (remaining <= 0) {
        _dangerZoneNotifier.value = false;
        _dangerPulseNotifier.value = false;
        _lastDangerHapticSecond = -1;
        // Schedule advance only once per round expiry (_graceDelayActive guard).
        // The 7s delay mirrors UPLOAD_GRACE_MS on the server: in-flight uploads
        // have until T+7s to be accepted before advanceRoundOrFinish fires.
        if (!_graceDelayActive &&
            _shouldAttemptAdvanceFromClient(
              currentStatus: status,
              roundActive: isRoundActive,
            )) {
          _graceDelayActive = true;
          final capturedToken = _advanceAttemptToken;
          Future.delayed(
            const Duration(milliseconds: _uploadGraceMs),
            () {
              if (!mounted) return;
              if (movedToResult) return;
              if (_advanceAttemptToken != capturedToken) return;
              _graceDelayActive = false;
              _attemptAdvanceRoundOrFinish();
            },
          );
        }
        return;
      }

      if (DebateAlertService.dangerFlashEnabled && remaining <= 10) {
        _dangerZoneNotifier.value = true;
        _dangerPulseNotifier.value = !_dangerPulseNotifier.value;
        if (_lastDangerHapticSecond != remaining) {
          _lastDangerHapticSecond = remaining;
          HapticFeedback.lightImpact();
          if (remaining <= 5) {
            SoundService.instance.play(SFX.tick);
          }
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
    if (status == 'active') {
      _playBellCueIfNeeded(nextRound: roundIndex, force: true);
    }

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
      final previousStatus = status;

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

      if (newStatus == 'active' &&
          (previousStatus != 'active' || previousRound != roundIndex)) {
        _playBellCueIfNeeded(nextRound: roundIndex);
      }

      if (newStatus == 'finished' && previousStatus != 'finished') {
        HapticFeedback.heavyImpact();
      }

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

  String _heroTagForSide(int side) {
    return 'debate-${widget.debateId}-fighter-$side';
  }

  void _playBellCueIfNeeded({
    required int nextRound,
    bool force = false,
  }) {
    if (status != 'active' || !isRoundActive) return;
    final cueKey = 'round-$nextRound';
    if (!force && cueKey == _lastBellCueKey) return;
    _lastBellCueKey = cueKey;
    HapticFeedback.mediumImpact();
    SoundService.instance.play(SFX.bell);
  }

  Widget _buildVoteBar() {
    final totalVotes = votes1 + votes2;
    final leftFlex = totalVotes == 0 ? 1 : votes1;
    final rightFlex = totalVotes == 0 ? 1 : votes2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 4,
        color: Colors.white.withValues(alpha: 0.08),
        child: Row(
          children: [
            Expanded(
              flex: leftFlex,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                color: VerdictStyle.fighterBlue,
              ),
            ),
            Expanded(
              flex: rightFlex,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                color: VerdictStyle.fighterRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeLeft(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final mm = (safe ~/ 60).toString().padLeft(2, '0');
    final ss = (safe % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Widget _buildCompactAvatar({
    required String name,
    required Color color,
    required String heroTag,
  }) {
    final safeName = name.trim().isEmpty ? '?' : name.trim();
    final initial = safeName.isEmpty ? '?' : safeName.substring(0, 1);
    return Hero(
      tag: heroTag,
      child: CircleAvatar(
        radius: 14,
        backgroundColor: color.withValues(alpha: 0.24),
        child: Text(
          initial,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _onMessagesScroll(ScrollNotification notification) {
    // Only react to scroll END — calling setState during active scroll
    // interrupts the gesture and freezes the ListView.
    if (notification.metrics.axis != Axis.vertical) return;
    if (notification is! ScrollEndNotification) return;

    final shouldCollapse = notification.metrics.pixels > _snapThresholdPx;
    if (shouldCollapse == _headerCollapsed || !mounted) return;
    setState(() {
      _headerCollapsed = shouldCollapse;
    });
  }

  Color _timerColor(int timeLeft) {
    if (timeLeft <= 5) return const Color(0xFFFF3B30);
    if (timeLeft <= 10) return const Color(0xFFFF6B6B);
    return Colors.white;
  }

  Widget _buildCompactHeader({
    required AppLocalizations l10n,
    required String fighter1Label,
    required String fighter2Label,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: _timeLeftNotifier,
      builder: (context, timeLeft, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _dangerZoneNotifier,
          builder: (context, isDanger, __) {
            return ValueListenableBuilder<bool>(
              valueListenable: _dangerPulseNotifier,
              builder: (context, pulse, ___) {
                final isActive = status == 'active';
                final timerText =
                    isActive ? _formatTimeLeft(timeLeft) : '--:--';
                final compactHeight = _headerCollapsed ? 0.0 : 92.0;
                final borderColor = isDanger
                    ? (pulse
                        ? const Color(0x44FF6B6B)
                        : const Color(0x22FF6B6B))
                    : Colors.white10;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: compactHeight,
                  margin: EdgeInsets.fromLTRB(12, _headerCollapsed ? 0 : 4, 12,
                      _headerCollapsed ? 0 : 6),
                  padding: EdgeInsets.fromLTRB(10, _headerCollapsed ? 0 : 8, 10,
                      _headerCollapsed ? 0 : 8),
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A2035),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildCompactAvatar(
                            name: fighter1Label,
                            color: VerdictStyle.fighterBlue,
                            heroTag: _heroTagForSide(1),
                          ),
                          const SizedBox(width: 6),
                          _buildCompactAvatar(
                            name: fighter2Label,
                            color: VerdictStyle.fighterRed,
                            heroTag: _heroTagForSide(2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$votes1:$votes2',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            timerText,
                            style: TextStyle(
                              fontSize: _headerCollapsed ? 13 : 14,
                              fontWeight: FontWeight.w900,
                              color: _timerColor(timeLeft),
                            ),
                          ),
                        ],
                      ),
                      if (!_headerCollapsed) ...[
                        const SizedBox(height: 8),
                        Text(
                          status == 'finished'
                              ? l10n.finishedStatus
                              : (status == 'waiting'
                                  ? l10n.waitingOpponent
                                  : (isFighter
                                      ? (isMyTurn
                                          ? l10n.yourTurnUpper
                                          : l10n.opponentTurnUpper)
                                      : l10n.viewerUpper)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                        if (_canAcceptPending)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isAcceptingPending
                                  ? null
                                  : _acceptPendingDebate,
                              style: TextButton.styleFrom(
                                foregroundColor: VerdictStyle.accentGold,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: const Size(0, 26),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                _isAcceptingPending
                                    ? l10n.accepting
                                    : l10n.acceptChallenge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 6),
                      _buildVoteBar(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPinnedTopStrip() {
    return ValueListenableBuilder<int>(
      valueListenable: _timeLeftNotifier,
      builder: (context, timeLeft, _) {
        final timerText =
            status == 'active' ? _formatTimeLeft(timeLeft) : '--:--';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '$votes1:$votes2',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  timerText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: _timerColor(timeLeft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildVoteBar(),
          ],
        );
      },
    );
  }

  void _cancelPendingAdvanceIfNeeded({
    required int previousRound,
    required int nextRound,
    required String nextStatus,
  }) {
    if (nextStatus == 'finished' || nextRound != previousRound) {
      _advanceAttemptToken++;
      _advancePending = false;
      _graceDelayActive = false;
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

    // Дедуп по раунду+спикеру: если уже пытались для этого хода — не спамим.
    if (_lastAdvanceRoundAttempt == roundIndex &&
        _lastAdvanceSpeakerAttempt == activeSpeakerId &&
        lastAt != null) {
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
    _lastAdvanceSpeakerAttempt = activeSpeakerId;

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
    // Optimistic update — block duplicate taps immediately
    HapticFeedback.lightImpact();
    SoundService.instance.play(SFX.click);
    setState(() {
      hasVotedThisRound = true;
      votedSideThisRound = 1;
      _voteStatusRoundIndex = roundIndex;
    });
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
    // Optimistic update — block duplicate taps immediately
    HapticFeedback.lightImpact();
    SoundService.instance.play(SFX.click);
    setState(() {
      hasVotedThisRound = true;
      votedSideThisRound = 2;
      _voteStatusRoundIndex = roundIndex;
    });
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
    HapticFeedback.selectionClick();
    SoundService.instance.play(SFX.whoosh);
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

  // Input bar UI extracted to lib/widgets/debate_input_bar.dart

  // ─── VOICE RECORDING ──────────────────────────────────────

  Future<void> _startRecording() async {
    if (_isRecording || _isUploadingMedia) return;
    if (!isFighter || !isMyTurn || status == 'finished') return;

    try {
      if (!await _audioRecorder.hasPermission()) return;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/verdict_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1, // mono — eliminates stereo phase artifacts & crackling
        ),
        path: path,
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _recordingStartTime = DateTime.now();
      });
    } catch (e) {
      debugPrint('[Voice] Start recording error: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;

    try {
      final path = await _audioRecorder.stop();
      if (!mounted) return;

      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inSeconds
          : 0;

      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingStartTime = null;
      });

      if (path == null || path.isEmpty) return;
      if (duration < 1) {
        // Too short — delete and ignore
        try { File(path).deleteSync(); } catch (_) {}
        return;
      }

      HapticFeedback.lightImpact();
      await _sendMediaMessage(
        filePath: path,
        messageType: 'voice',
        mediaDuration: duration,
      );
    } catch (e) {
      debugPrint('[Voice] Stop recording error: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    try {
      await _audioRecorder.stop();
      if (_recordingPath != null) {
        try { File(_recordingPath!).deleteSync(); } catch (_) {}
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingStartTime = null;
      });
    }
  }

  // ─── IMAGE PICKING ────────────────────────────────────────

  Future<void> _pickAndSendImage() async {
    if (_isUploadingMedia || _isRecording) return;
    if (!isFighter || !isMyTurn || status == 'finished') return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;

      HapticFeedback.lightImpact();
      await _sendMediaMessage(
        filePath: picked.path,
        messageType: 'image',
      );
    } catch (e) {
      debugPrint('[Image] Pick error: $e');
    }
  }

  // ─── YIELD TURN ───────────────────────────────────────────

  Future<void> _onYieldPressed() async {
    if (_isYieldingTurn) return;
    final l10n = AppLocalizations.of(context)!;

    // Flow B: upload in progress → warn about cancellation.
    // Flow A: no upload → simple confirmation.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _isUploadingMedia
          ? AlertDialog(
              backgroundColor: const Color(0xFF141C2F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: Colors.orange.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              title: const Text(
                'Отменить отправку и уступить?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              content: const Text(
                'Ваше сообщение ещё загружается. Если уступить сейчас, загрузка будет отменена.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    'Продолжить загрузку',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Отменить и уступить',
                    style: TextStyle(
                      color: Color(0xFFFFA500),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            )
          : AlertDialog(
              backgroundColor: const Color(0xFF141C2F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              title: const Text(
                'Уступить слово?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              content: const Text(
                'Ваше оставшееся время будет передано оппоненту.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    'Отмена',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Уступить',
                    style: TextStyle(
                      color: Color(0xFFFFA500),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Policy B: cancel any in-flight upload before yielding.
    if (_isUploadingMedia) {
      setState(() => _isUploadingMedia = false);
    }

    setState(() => _isYieldingTurn = true);
    try {
      await _functions
          .httpsCallable('yieldTurn')
          .call({'debateId': widget.debateId});
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapDebateCallableError(l10n, e, fallbackMessage: l10n.errorPrefix),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorPrefix}: не удалось уступить слово.')),
      );
    } finally {
      if (mounted) setState(() => _isYieldingTurn = false);
    }
  }

  // ─── SHARED MEDIA UPLOAD & SEND ───────────────────────────

  Future<void> _sendMediaMessage({
    required String filePath,
    required String messageType,
    int mediaDuration = 0,
  }) async {
    if (_isUploadingMedia) return;

    final l10n = AppLocalizations.of(context)!;
    _bootstrapCurrentUserIdentity();
    final senderName =
        _bestEffortName(FirebaseAuth.instance.currentUser).trim();
    if (senderName.isEmpty) return;

    setState(() => _isUploadingMedia = true);
    bool succeeded = false;

    try {
      // 1. Upload to Firebase Storage
      String? downloadUrl;
      if (messageType == 'voice') {
        downloadUrl = await MediaUploadService.instance.uploadVoice(
          debateId: widget.debateId,
          uid: currentUserId,
          filePath: filePath,
        );
      } else {
        downloadUrl = await MediaUploadService.instance.uploadImage(
          debateId: widget.debateId,
          uid: currentUserId,
          filePath: filePath,
        );
      }

      if (downloadUrl == null) {
        throw Exception('Upload returned null URL');
      }
      if (!mounted) return;

      // 2. Call Cloud Function with media data
      final callable = _functions.httpsCallable(
        'sendDebateMessage',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call({
        'debateId': widget.debateId,
        'text': '',
        'senderName': senderName,
        'messageType': messageType,
        'mediaUrl': downloadUrl,
        if (mediaDuration > 0) 'mediaDuration': mediaDuration,
      });

      succeeded = true;
      if (!mounted) return;
      SoundService.instance.play(SFX.whoosh);
      HapticFeedback.selectionClick();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // Turn-expiry errors mean the grace window passed before the upload
      // completed. Retrying won't succeed — the round has already switched.
      // Show a brief, non-blocking toast and discard silently.
      final reason =
          (e.details is Map ? e.details['reason'] : null)?.toString() ?? '';
      const turnExpiryCodes = {
        'TURN_NOT_ACTIVE_SPEAKER',
        'TURN_TIME_EXPIRED',
        'ROUND_NOT_ACTIVE',
      };
      if (turnExpiryCodes.contains(reason)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            content: Text('Время истекло — сообщение не отправлено.'),
          ),
        );
        return;
      }
      // All other CF errors: show with Retry option.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(mapDebateCallableError(l10n, e,
              fallbackMessage: l10n.errorPrefix)),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _sendMediaMessage(
              filePath: filePath,
              messageType: messageType,
              mediaDuration: mediaDuration,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('${l10n.errorPrefix}: Upload failed. Check connection.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _sendMediaMessage(
              filePath: filePath,
              messageType: messageType,
              mediaDuration: mediaDuration,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
      // Only delete temp file on success — keep it for retry on failure.
      if (succeeded) {
        try { File(filePath).deleteSync(); } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roundCountdownTicker?.cancel();
    debateSub?.cancel();
    _advanceAttemptToken++;
    _advancePending = false;
    _messageController.dispose();
    _timeLeftNotifier.dispose();
    _dangerZoneNotifier.dispose();
    _dangerPulseNotifier.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
      // false: keyboard avoidance is handled manually via AnimatedPadding +
      // viewInsets.bottom in the body Stack. Using true here would double-pad
      // and leave an empty strip when the keyboard dismisses.
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 6,
        title: _buildPinnedTopStrip(),
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
            builder: (context, _) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Column(
                  children: [
                    _buildCompactHeader(
                      l10n: l10n,
                      fighter1Label: displayFighter1Name,
                      fighter2Label: displayFighter2Name,
                    ),
                    if (isViewer && !_headerCollapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    (status == 'finished' || hasVotedThisRound)
                                        ? null
                                        : vote1,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: VerdictStyle.fighterBlue
                                        .withValues(alpha: 0.6),
                                  ),
                                  minimumSize: const Size(0, 34),
                                  foregroundColor: VerdictStyle.fighterBlue,
                                ),
                                child: Text('${l10n.voteFor} 1'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    (status == 'finished' || hasVotedThisRound)
                                        ? null
                                        : vote2,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: VerdictStyle.fighterRed
                                        .withValues(alpha: 0.6),
                                  ),
                                  minimumSize: const Size(0, 34),
                                  foregroundColor: VerdictStyle.fighterRed,
                                ),
                                child: Text('${l10n.voteFor} 2'),
                              ),
                            ),
                          ],
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
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xCC0D111B),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                _onMessagesScroll(notification);
                                return false;
                              },
                              child: DebateMessagesList(
                                debateId: widget.debateId,
                                fighter1Id: fighter1,
                                showWaitingTurn: isFighter &&
                                    status != 'finished' &&
                                    !isMyTurn,
                                waitingText: l10n.waitingYourTurn,
                              ),
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
                          child: DebateInputBar(
                            isMyTurn: isMyTurn,
                            isSendingMessage: _isSendingMessage,
                            isUploading: _isUploadingMedia,
                            isRecording: _isRecording,
                            isRoundActive: isRoundActive,
                            isYielding: _isYieldingTurn,
                            recordingStartTime: _recordingStartTime,
                            textController: _messageController,
                            onSend: sendMessage,
                            onMicLongPressStart: (_) => _startRecording(),
                            onMicLongPressEnd: (_) => _stopRecordingAndSend(),
                            onPickImage: _pickAndSendImage,
                            onCancelRecording: _cancelRecording,
                            onSendRecording: _stopRecordingAndSend,
                            onYield: isMyTurn && isRoundActive
                                ? _onYieldPressed
                                : null,
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
