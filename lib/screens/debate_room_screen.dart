import '../services/pending_text_send.dart';
import '../utils/pending_message_request.dart';
import '../utils/compact_notice.dart';
import 'package:verdict/firebase_session.dart';
import 'package:verdict/firestore_database.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
// dart:io is only available on mobile/desktop, not Web.
// ignore: avoid_web_libraries_in_flutter
import 'dart:io' if (dart.library.html) 'dart:html' as io_shim;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import '../models/debate.dart';
import '../painters/chat_pattern_painter.dart';
import '../widgets/debate_messages_list.dart';
import '../widgets/debate_input_bar.dart';
import '../widgets/opponent_activity_indicator.dart';
import '../services/media_upload_service.dart';
import '../services/referee_service.dart';
import '../services/debate_alert_service.dart';
import '../services/sound_service.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/name_utils.dart';
import '../utils/vote_totals.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';

import 'package:go_router/go_router.dart';

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
    with WidgetsBindingObserver, TickerProviderStateMixin {
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

  int _voteStatusRequestToken = 0;

  void _refreshMyVoteStatus() {
    final requestedRound = roundIndex;
    final requestToken = ++_voteStatusRequestToken;
    setState(() {
      hasVotedThisRound = false;
      votedSideThisRound = 0;
      _voteStatusRoundIndex = requestedRound;
    });
    unawaited(() async {
      try {
        final response = await _functions.httpsCallable('getMyVoteStatus',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        ).call({'debateId': widget.debateId, 'scope': 'round'});
        final data = response.data;
        if (!mounted || requestToken != _voteStatusRequestToken ||
            roundIndex != requestedRound || hasVotedThisRound || data is! Map ||
            data['roundIndex'] != requestedRound) {
          return;
        }
        setState(() {
          hasVotedThisRound = data['hasVoted'] == true;
          final side = data['side'];
          votedSideThisRound = side == 1 || side == 2 ? side as int : 0;
        });
      } catch (error) {
        // A failed status read does not consume a vote. The server still checks
        // the ballot atomically when the user taps again.
        debugPrint('Vote status could not be refreshed: $error');
      }
    }());
  }

  final TextEditingController _messageController = TextEditingController();
  late final TextDraftTracker _textDraft;
  final FirebaseFunctions _functions = appFunctions;
  Timer? _typingDebouncer;
  Timer? _activityClearTimer;

  Debate? _debate;
  bool _roomStateConfirmed = false;
  int _roomListenEpoch = 0;
  int _roomSnapshotRevision = 0;
  int _roomRefreshEpoch = 0;
  int _confirmedRound = 0;
  bool _confirmedFinished = false;

  VoteTotals? _liveVoteTotals;
  bool _usesVoteTallies = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _voteTalliesSub;
  int get votes1 => _liveVoteTotals?.votes1 ?? _debate?.votes1 ?? 0;
  int get votes2 => _liveVoteTotals?.votes2 ?? _debate?.votes2 ?? 0;

  void _syncVoteTallies(Map<String, dynamic> data) {
    final enabled = data['voteTallyVersion'] == 1;
    if (enabled == _usesVoteTallies) return;
    _usesVoteTallies = enabled;
    _voteTalliesSub?.cancel();
    _voteTalliesSub = null;
    _liveVoteTotals = null;
    if (!enabled) return;
    _voteTalliesSub = appFirestore.collection('debates').doc(widget.debateId)
        .collection('vote_tallies').limit(16).snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() => _liveVoteTotals = VoteTotals.fromShards(
        snapshot.docs.map((doc) => doc.data()),
      ));
    }, onError: (Object error) {
      if (!mounted) return;
      debugPrint('Live vote totals unavailable: $error');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.voteTotalsUnavailable),
      ));
    });
  }

  String get topic => _debate?.topic ?? '';
  String get debateType => _debate?.debateType ?? 'open';
  String get fighter1 => _debate?.fighter1 ?? '';
  String get fighter2 => _debate?.fighter2 ?? '';
  String get opponentId => _debate?.opponentId ?? '';
  String get creatorId => _debate?.creatorId ?? '';

  String _localFighter1Name = '';
  String _localFighter2Name = '';
  String get fighter1Name => _localFighter1Name.isNotEmpty ? _localFighter1Name : (_debate?.fighter1Name ?? '');
  set fighter1Name(String v) => _localFighter1Name = v;
  String get fighter2Name => _localFighter2Name.isNotEmpty ? _localFighter2Name : (_debate?.fighter2Name ?? '');
  set fighter2Name(String v) => _localFighter2Name = v;

  String get status => _debate?.status ?? 'active';
  String get activeSpeakerId => _debate?.activeSpeakerId ?? '';
  int get roundIndex => _debate?.roundIndex ?? 1;
  int get totalRounds => _debate?.totalRounds ?? 3;

  bool _localIsRoundActive = true;
  bool _isRoundActiveMutated = false;
  bool get isRoundActive => _isRoundActiveMutated ? _localIsRoundActive : (_debate?.isRoundActive ?? true);
  set isRoundActive(bool v) {
    _localIsRoundActive = v;
    _isRoundActiveMutated = true;
  }

  int pendingPenaltySecondsForMe = 0;
  bool hasVotedThisRound = false;
  int votedSideThisRound = 0;
  int _voteStatusRoundIndex = -1;
  bool get isTimerRunning => _debate?.isTimerRunning ?? false;
  Timestamp? get startTime => _debate?.startTime;
  String get creationMode => _debate?.creationMode ?? 'public_feed';
  String get invitedUserId => _debate?.invitedUserId ?? '';
  bool _isAcceptingPending = false;

  int _sanitizeDuration(dynamic value, int fallback) {
    final candidate = value is int ? value : (value is num ? value.toInt() : fallback);
    return _durationOptions.contains(candidate) ? candidate : fallback;
  }
  int _sanitizeRounds(dynamic value, int fallback) {
    final candidate = value is int ? value : (value is num ? value.toInt() : fallback);
    return _roundOptions.contains(candidate) ? candidate : fallback;
  }

  int get _termsCreatorDuration => _sanitizeDuration(_debate?.termsProposalCreator['roundDurationSeconds'], _sanitizeDuration(_debate?.durationSeconds, 180));
  int get _termsCreatorRounds => _sanitizeRounds(_debate?.termsProposalCreator['totalRounds'], _sanitizeRounds(_debate?.totalRounds, 3));
  int get _termsResolvedDuration => _sanitizeDuration(_debate?.termsResolved['roundDurationSeconds'], _termsCreatorDuration);

  bool isLoading = true;
  bool movedToResult = false;
  bool _accessDeniedHandled = false;

  // ─── MEDIA STATE ──────────────────────────────────────────
  bool _isRecording = false;
  bool _isUploadingMedia = false;
  String _activitySpeakerSubscribed = '';
  String? _pendingMediaPath;
  String? _pendingMediaRequestId;
  final Set<String> _confirmedMediaIds = {};
  final Set<String> _sentVoiceFiles = {};

  void _mediaConfirmed(String id) {
    _confirmedMediaIds.add(id);
    if (!mounted || _pendingMediaRequestId != id) return;
    setState(() { _pendingMediaPath = null; _pendingMediaType = null; _pendingMediaRequestId = null; _isUploadingMedia = false; });
  }
  String? _pendingMediaType;
  bool _pendingMediaFailed = false;
  VoidCallback? _retryPendingMedia;
  bool _bankEnabled = false;
  Map<String, dynamic> _timeBanks = {};
  Timer? _presenceTimer;
  bool _presenceBusy = false;
  bool _roomVisible = true;
  int? _liveViewers;

  Future<void> _heartbeat({bool present = true}) async {
    if (_presenceBusy && present) return;
    if (present && (!_roomVisible || isLoading || status == 'finished')) return;
    _presenceBusy = true;
    try {
      final result = await _functions.httpsCallable('heartbeatDebateViewer',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
        .call({'debateId': widget.debateId, 'present': present});
      final data = result.data;
      if (mounted && present && data is Map && data['viewers'] is num) {
        setState(() => _liveViewers = (data['viewers'] as num).toInt());
      }
    } catch (_) { /* A missing count must never be presented as a confirmed zero. */ }
    finally { _presenceBusy = false; }
  }

  // Non-null only during a multi-photo batch upload. Format: "current/total".
  String? _batchUploadLabel;
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final RecorderController _recorderController;
  String? _recordingPath;
  DateTime? _recordingStartTime;

  Timer? _roundCountdownTicker;
  StreamSubscription<DocumentSnapshot>? _debateSub;
  StreamSubscription<DocumentSnapshot>? _activitySub;
  String _activeSpeakerActivity = ''; // 'typing', 'recording', 'image', ''
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

  // ─── ROUND TRANSITION OVERLAY ────────────────────────────
  late final AnimationController _overlayCtrl;
  Timer? _overlayTimer;
  String? _roundOverlayMessage;
  // Suppresses overlay on the very first Firestore snapshot (initial load).
  bool _debateSubFirstEvent = true;
  // True from timer-zero until Firestore confirms the new round/speaker.
  // Shows a "Transitioning..." banner so the user isn't staring at a frozen 0:00.
  bool _isTransitioning = false;
  String _lastHydratedFighter1Uid = '';
  String _lastHydratedFighter2Uid = '';

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  // _sanitize functions moved above





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
        final snap = await appFirestore
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
        final snap = await appFirestore
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
    if (context.canPop()) context.pop();
  }

  @override
  void initState() {
    super.initState();
    _textDraft = TextDraftTracker(_messageController);
    _restorePendingText();
    WidgetsBinding.instance.addObserver(this);
    _timeLeftNotifier = ValueNotifier<int>(60);
    _dangerZoneNotifier = ValueNotifier<bool>(false);
    _dangerPulseNotifier = ValueNotifier(false);

    _recorderController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 22050
      ..bitRate = 64000; // 64 kbps AAC keeps voice uploads compact.

    _overlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _bootstrapCurrentUserIdentity();
    _startRoundCountdownTicker();
    _loadDebate().then((_) { if (mounted) _heartbeat(); });
    _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) => _heartbeat());
  }

  /// Releases the microphone when the app is backgrounded or interrupted
  /// by an incoming call. Prevents mic lock and silent crash on iOS/Android.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _roomVisible = state == AppLifecycleState.resumed;
    _roomRefreshEpoch++;
    _roomStateConfirmed = false;
    if (_roomVisible) {
      _timeLeftNotifier.value = _remainingSecondsFromRoundEnd();
      if (_debateSub != null) unawaited(_refreshRoomFromServer());
      _heartbeat();
    } else {
      _heartbeat(present: false);
    }
    if (mounted) setState(() {});
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isRecording) {
        debugPrint('[Voice] App backgrounded — cancelling active recording.');
        _cancelRecording();
      }
    }
  }

  void _bootstrapCurrentUserIdentity() {
    final user = appAuth.currentUser;
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
      final userSnap = await appFirestore
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
            Duration(milliseconds: _bankEnabled ? 0 : _uploadGraceMs),
            () {
              if (!mounted) return;
              if (movedToResult) return;
              if (_advanceAttemptToken != capturedToken) return;
              _graceDelayActive = false;
              _attemptAdvanceRoundOrFinish();
            },
          );
        }
        // Optimistic lock — disable input instantly when time expires.
        // Must come AFTER scheduling advance (which checks isRoundActive).
        if (isRoundActive) {
          setState(() {
            isRoundActive = false;
            _isTransitioning = true; // Show banner while waiting for Firestore
          });
        }
        return;
      }

      if (DebateAlertService.dangerFlashEnabled && remaining <= 10) {
        _dangerZoneNotifier.value = true;
        _dangerPulseNotifier.value = !_dangerPulseNotifier.value;
        if (_lastDangerHapticSecond != remaining) {
          _lastDangerHapticSecond = remaining;
          // Last 5s: heavy tick-tock impact. 6–10s: gentle pulse.
          if (remaining <= 5) {
            HapticFeedback.heavyImpact();
            SoundService.instance.play(SFX.tick);
          } else {
            HapticFeedback.lightImpact();
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
        appFirestore.collection('debates').doc(widget.debateId);
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
      if (context.canPop()) context.pop();
      return;
    }

    if (!mounted) return;

    if (data == null) {
      setState(() {
        isLoading = false;
        _debate = null;
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

    _roomStateConfirmed = !snap.metadata.isFromCache && !snap.metadata.hasPendingWrites;
    _debate = Debate.fromMap(widget.debateId, data);
    if (_roomStateConfirmed) {
      _confirmedRound = roundIndex;
      _confirmedFinished = status == 'finished';
    }
    _syncVoteTallies(data);

    await _hydrateUserNameFromFirestore();
    if (!mounted) return;
    await _hydrateFighterNamesFromUsers();
    if (!mounted) return;

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

    if (!mounted) return;
    _subscribeToDebate(ref);
  }

  void _subscribeToDebate(DocumentReference<Map<String, dynamic>> ref) {
    final epoch = ++_roomListenEpoch;
    _debateSub?.cancel();
    _debateSubFirstEvent = true;
    _debateSub = ref.snapshots(includeMetadataChanges: true).listen((doc) {
      if (!mounted || epoch != _roomListenEpoch) return;
      _applyRoomSnapshot(doc);
    }, onError: (_) {
      if (!mounted || epoch != _roomListenEpoch) return;
      _roomStateConfirmed = false;
      _handleAccessDeniedAndExit();
    });
  }

  Future<void> _refreshRoomFromServer() async {
    final epoch = _roomListenEpoch;
    final revision = _roomSnapshotRevision;
    final refreshEpoch = _roomRefreshEpoch;
    try {
      final snapshot = await appFirestore.collection('debates').doc(widget.debateId)
          .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 12));
      if (!mounted || epoch != _roomListenEpoch || !_roomVisible ||
          revision != _roomSnapshotRevision || refreshEpoch != _roomRefreshEpoch) {
        return;
      }
      _applyRoomSnapshot(snapshot);
    } catch (_) {
      // Reconnect failure is not surrender. Keep the draft and wait for stream confirmation.
    }
  }

  void _applyRoomSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
      // Cached/local events are previews, never confirmation of a current turn.
      if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites) {
        _roomSnapshotRevision++;
        setState(() => _roomStateConfirmed = false);
        return;
      }
      final liveData = doc.data() ?? {};
      final previousRound = roundIndex;
      final previousStatus = status;
      final previousSpeaker = activeSpeakerId;

      if (!mounted) return;

      if (!_canAccessDebateData(liveData)) {
        _handleAccessDeniedAndExit();
        return;
      }

      final newStatus = _normalizeStatus(liveData['status'] ?? status,
          fallback: status == 'finished' ? 'finished' : 'waiting');
      final incomingRound = liveData['roundIndex'];
      if ((incomingRound is num && incomingRound < _confirmedRound) ||
          (_confirmedFinished && newStatus != 'finished')) {
        return;
      }
      _roomStateConfirmed = true;
      _roomSnapshotRevision++;
      if (incomingRound is num) _confirmedRound = incomingRound.toInt();
      _confirmedFinished = newStatus == 'finished';
      _syncRoundCountdownFromData(liveData, newStatus);

      // Listener for active speaker's activity
      final currentActiveSpeaker = (liveData['activeSpeakerId'] ?? '').toString();
      if (currentActiveSpeaker != _activitySpeakerSubscribed && currentActiveSpeaker.isNotEmpty) {
        _activitySub?.cancel();
        _activitySpeakerSubscribed = currentActiveSpeaker;
        _activitySub = appFirestore
            .collection('debates')
            .doc(widget.debateId)
            .collection('activity')
            .doc(currentActiveSpeaker)
            .snapshots()
            .listen((actSnap) {
          if (!mounted) return;
          final actData = actSnap.data();
          if (actData != null) {
            final st = (actData['status'] ?? '').toString();
            final updated = actData['updatedAt'] as Timestamp?;
            if (updated != null && DateTime.now().difference(updated.toDate()).inSeconds < 10) {
              setState(() => _activeSpeakerActivity = st);
            } else {
              setState(() => _activeSpeakerActivity = '');
            }
          } else {
            setState(() => _activeSpeakerActivity = '');
          }
        }, onError: (Object error) { debugPrint('Activity unavailable: $error'); });
      }

      _debate = Debate.fromMap(widget.debateId, liveData);
      _syncVoteTallies(liveData);
      _bankEnabled = liveData['clockMode'] == 'bank_v1';
      _timeBanks = liveData['timeBankMs'] is Map ? Map<String, dynamic>.from(liveData['timeBankMs']) : {};
      setState(() {
        _isRoundActiveMutated = false; // Reset optimistic lock
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

      // Clear transitioning banner — Firestore has confirmed the new state.
      if (_isTransitioning) {
        _isTransitioning = false;
        // No extra setState needed: the surrounding setState already covers it.
      }

      // ── Round transition overlay (fighters only, not on first event) ──
      if (isFighter && !_debateSubFirstEvent) {
        if (newStatus == 'active' && previousStatus != 'active') {
          // Debate just started.
          _showRoundOverlay('БОЙ НАЧАЛСЯ!');
        } else if (newStatus == 'active' && roundIndex > previousRound) {
          // New round started (covers round N → round N+1).
          _showRoundOverlay('РАУНД $roundIndex');
        } else if (newStatus == 'active' &&
            activeSpeakerId.isNotEmpty &&
            activeSpeakerId == currentUserId &&
            previousSpeaker != currentUserId) {
          // Turn passed to me within the same round.
          _showRoundOverlay('ВАШ ХОД!');
        }
      }
      _debateSubFirstEvent = false;

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
        context.replace('/result/${widget.debateId}');
      }
  }

  String get _effectiveCurrentUid {
    if (currentUserId.isNotEmpty) return currentUserId;
    return appAuth.currentUser?.uid ?? '';
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

  bool get canSendText => _roomVisible && _roomStateConfirmed &&
      _remainingSecondsFromRoundEnd() > 0 && isMyTurn;

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
    if (timeLeft <= 5) return const Color(0xFFFF2222);
    if (timeLeft <= 10) return const Color(0xFFFF4444);
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
                final compactHeight = _headerCollapsed ? 0.0 : (_bankEnabled ? 148.0 : 112.0);
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
                              '$votes1:$votes2 · ${_liveViewers == null ? '—' : '≈$_liveViewers'} ${l10n.spectatorsLiveLabel}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          AnimatedScale(
                            scale: isDanger && pulse ? 1.10 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: Text(
                              timerText,
                              style: TextStyle(
                                fontSize: _headerCollapsed ? 13 : 14,
                                fontWeight: FontWeight.w900,
                                color: _timerColor(timeLeft),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!_headerCollapsed) ...[
                        if (_bankEnabled) Row(children: [
                          for (final side in [1, 2]) Expanded(child: TextButton(
                            onPressed: isMyTurn && isRoundActive && !_isYieldingTurn && currentUserId == (side == 1 ? fighter1 : fighter2) ? _onYieldPressed : null,
                            child: Text('${side == 1 ? fighter1Label : fighter2Label}  ${activeSpeakerId == (side == 1 ? fighter1 : fighter2) ? _formatTimeLeft(timeLeft) : '+${_formatTimeLeft(((_timeBanks[side == 1 ? fighter1 : fighter2] as num?)?.toInt() ?? 0) ~/ 1000)}'}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: side == 1 ? VerdictStyle.fighterBlue : VerdictStyle.fighterRed)),
                          )),
                        ]),
                        const SizedBox(height: 4),
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
        // Read danger/pulse values inline — the timeLeft notifier fires every
        // second at the same rate, so these values are always current.
        final isDanger = _dangerZoneNotifier.value;
        final pulse = _dangerPulseNotifier.value;
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
                AnimatedScale(
                  scale: isDanger && pulse ? 1.10 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Text(
                    timerText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _timerColor(timeLeft),
                    ),
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
    final delayMs = _stableHash(hashSeed) % (_bankEnabled ? 150 : _advanceJitterWindowMs);

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

  Future<void> vote1() => _castRoundVote(1);
  Future<void> vote2() => _castRoundVote(2);

  Future<void> _castRoundVote(int side) async {
    final l10n = AppLocalizations.of(context)!;
    if (status != 'active' || !isViewer || hasVotedThisRound) return;
    final submittedRound = roundIndex;
    ++_voteStatusRequestToken;
    HapticFeedback.lightImpact();
    SoundService.instance.play(SFX.click);
    setState(() {
      hasVotedThisRound = true;
      votedSideThisRound = side;
      _voteStatusRoundIndex = submittedRound;
    });
    try {
      await _functions.httpsCallable('castVote',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      ).call({
        'debateId': widget.debateId,
        'side': side,
        'scope': 'round',
        'expectedRoundIndex': submittedRound,
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final details = error.details;
      final alreadyCast = details is Map && details['reason'] == 'VOTE_ALREADY_CAST';
      // A late failure from the previous round must not unlock or overwrite a
      // selection made in the current round.
      if (roundIndex == submittedRound && _voteStatusRoundIndex == submittedRound) {
        setState(() {
          hasVotedThisRound = alreadyCast;
          votedSideThisRound = 0;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mapDebateCallableError(l10n, error,
          fallbackMessage: l10n.voteSendFailed)),
      ));
    } catch (_) {
      if (!mounted) return;
      if (roundIndex == submittedRound && _voteStatusRoundIndex == submittedRound) {
        setState(() {
          hasVotedThisRound = false;
          votedSideThisRound = 0;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.voteSendFailed),
      ));
    }
  }

  Future<void> _restorePendingText() async {
    final uid = appAuth.currentUser?.uid;
    if (uid == null) return;
    final revision = _textDraft.revision;
    try {
      final pending = await PendingTextSend(uid, widget.debateId).load();
      if (mounted && appAuth.currentUser?.uid == uid &&
          pending != null && !_isSendingMessage) {
        _textDraft.restoreIfUnchanged(revision, pending.text);
      }
    } catch (_) { /* A corrupt local request is never sent automatically. */ }
  }

  Future<void> sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSendingMessage) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (!isFighter) return;
    if (status == 'finished') return;
    if (!canSendText) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.notYourTurn)),
      );
      return;
    }

    _bootstrapCurrentUserIdentity();
    final senderName =
        _bestEffortName(appAuth.currentUser).trim();
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
    final uid = appAuth.currentUser?.uid;
    if (uid == null) {
      setState(() => _isSendingMessage = false);
      return;
    }
    final pending = PendingTextSend(uid, widget.debateId);
    final submittedRevision = _textDraft.revision;
    try {
      await pending.send(text, roundIndex, callable: callable,
        isCurrentSession: () => mounted && appAuth.currentUser?.uid == uid);
      if (!mounted || appAuth.currentUser?.uid != uid) return;
      currentUserName = senderName;
      _textDraft.clearIfUnchanged(submittedRevision);
      _clearMyActivity();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted || appAuth.currentUser?.uid != uid) return;
      final details = e.details;
      final reason = details is Map ? (details['reason'] ?? '').toString() : '';
      if (reason == 'TURN_TIME_EXPIRED' || reason == 'ROUND_NOT_ACTIVE') {
        _attemptAdvanceRoundOrFinish();
      }
      if (!mounted || appAuth.currentUser?.uid != uid) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(mapDebateCallableError(
          l10n,
          e,
          fallbackMessage: l10n.errorPrefix,
        ))),
      );
    } catch (e) {
      if (!mounted || appAuth.currentUser?.uid != uid) return;
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
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Голосовые сообщения недоступны в Web-версии')),
      );
      return;
    }
    if (_isRecording || _isUploadingMedia) return;
    if (!isFighter || !isMyTurn || status == 'finished') return;

    try {
      if (!await _audioRecorder.hasPermission()) return;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/verdict_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorderController.record(path: path);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _publishActivity('recording');
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
      final path = await _recorderController.stop();
      if (!mounted) return;

      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inSeconds
          : 0;

      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingStartTime = null;
      });
      _clearMyActivity();

      if (path == null || path.isEmpty) return;
      if (duration < 1) {
        // Too short — delete and ignore
        if (!kIsWeb) {
          try { io_shim.File(path).deleteSync(); } catch (_) {}
        }
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
      await _recorderController.stop();
      if (_recordingPath != null) {
        if (!kIsWeb) {
          try { io_shim.File(_recordingPath!).deleteSync(); } catch (_) {}
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingStartTime = null;
      });
    }
    _clearMyActivity();
  }

  // ─── IMAGE PICKING ────────────────────────────────────────

  Future<void> _pickAndSendImage() async {
    if (_isUploadingMedia || _isRecording) return;
    if (!isFighter || !isMyTurn || status == 'finished') return;

    // Pick up to 10 photos at once.
    List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
    } catch (e) {
      debugPrint('[Image] Pick error: $e');
      return;
    }
    if (files.isEmpty || !mounted) return;
    if (files.length > 10) files = files.sublist(0, 10);

    HapticFeedback.lightImpact();
    for (final file in files) {
      if (!mounted || !isMyTurn) break;
      final sent = await _sendMediaMessage(filePath: file.path, messageType: 'image');
      if (!sent) break;
    }
  }

  // ─── YIELD TURN ───────────────────────────────────────────

  Future<void> _onYieldPressed() async {
    if (_isYieldingTurn) return;
    final l10n = AppLocalizations.of(context)!;

    if (!isMyTurn || !isRoundActive) return;
    HapticFeedback.lightImpact();
    final expectedRound = roundIndex;
    final expectedEnd = _roundEndsAtLocal?.millisecondsSinceEpoch;
    setState(() {
      _isYieldingTurn = true;
      isRoundActive = false; // Optimistic lock — disable input instantly.
    });
    try {
      await _functions
          .httpsCallable('yieldTurn')
          .call({'debateId': widget.debateId, if (expectedEnd != null) 'expectedTurn': {'round': expectedRound, 'endMs': expectedEnd}})
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorPrefix}: Превышено время ожидания.')),
      );
      if (roundIndex == expectedRound && _roundEndsAtLocal?.millisecondsSinceEpoch == expectedEnd) {
        setState(() => isRoundActive = true);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (roundIndex == expectedRound && _roundEndsAtLocal?.millisecondsSinceEpoch == expectedEnd) {
        setState(() => isRoundActive = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapDebateCallableError(l10n, e, fallbackMessage: l10n.errorPrefix),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      if (roundIndex == expectedRound && _roundEndsAtLocal?.millisecondsSinceEpoch == expectedEnd) {
        setState(() => isRoundActive = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorPrefix}: не удалось уступить слово.')),
      );
    } finally {
      if (mounted) setState(() => _isYieldingTurn = false);
    }
  }

  // ─── SHARED MEDIA UPLOAD & SEND ───────────────────────────

  Future<bool> _sendMediaMessage({required String filePath, required String messageType,
    int mediaDuration = 0, String? requestId, int? expectedRound}) async {
    if (_isUploadingMedia || !isMyTurn || !isRoundActive) return false;
    final id = requestId ?? PendingMessageRequest().forText(filePath).id;
    final round = expectedRound ?? roundIndex;
    setState(() {
      _isUploadingMedia = true; _pendingMediaPath = filePath; _pendingMediaRequestId = id;
      _pendingMediaType = messageType; _pendingMediaFailed = false;
      _retryPendingMedia = null;
    });
    _publishActivity(messageType);
    try {
      await MediaUploadService.instance.sendMedia(debateId: widget.debateId,
        uid: currentUserId, filePath: filePath, messageType: messageType,
        requestId: id, expectedRound: round, duration: mediaDuration);
      if (!mounted) return true;
      _mediaConfirmed(id);
      if (messageType == 'voice') _sentVoiceFiles.add(filePath);
      SoundService.instance.play(SFX.whoosh);
      HapticFeedback.selectionClick();
      // ImagePicker cache is managed by the OS. Never delete a user's original
      // photo while an image provider may still be decoding its preview.
      return true;
    } catch (_) {
      if (_confirmedMediaIds.contains(id)) return true;
      if (!mounted) return false;
      setState(() {
        _pendingMediaFailed = true;
        _retryPendingMedia = roundIndex == round ? () => _sendMediaMessage(filePath: filePath,
          messageType: messageType, mediaDuration: mediaDuration, requestId: id, expectedRound: round) : null;
      });
      showCompactNotice(context, AppLocalizations.of(context)!.messageSendFailed);
      return false;
    } finally {
      if (mounted && _pendingMediaRequestId == id) setState(() => _isUploadingMedia = false);
      if (_pendingMediaRequestId == null || _pendingMediaRequestId == id) _clearMyActivity();
    }
  }

  /// Shows a brief full-screen overlay (e.g. "РАУНД 2", "ВАШ ХОД!").
  /// Brief fade and 300ms hold keep the composer responsive between turns.
  void _showRoundOverlay(String message) {
    if (!mounted) return;
    _overlayTimer?.cancel();
    _overlayCtrl.stop();
    setState(() => _roundOverlayMessage = message);
    _overlayCtrl.forward(from: 0.0).then((_) {
      if (!mounted) return;
      _overlayTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _overlayCtrl.reverse().then((_) {
          if (mounted) setState(() => _roundOverlayMessage = null);
        });
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    unawaited(_heartbeat(present: false));
    _roundCountdownTicker?.cancel();
    _typingDebouncer?.cancel();
    _activityClearTimer?.cancel();
    _overlayTimer?.cancel();
    _roomListenEpoch++;
    _debateSub?.cancel();
    _voteTalliesSub?.cancel();
    _voteStatusRequestToken++;
    _activitySub?.cancel();
    _clearMyActivity();
    _advanceAttemptToken++;
    _advancePending = false;
    for (final path in _sentVoiceFiles) {
      if (!kIsWeb) { try { io_shim.File(path).deleteSync(); } catch (_) {} }
    }
    _textDraft.dispose();
    _messageController.dispose();
    _timeLeftNotifier.dispose();
    _dangerZoneNotifier.dispose();
    _dangerPulseNotifier.dispose();
    _overlayCtrl.dispose();
    _audioRecorder.dispose();
    _recorderController.dispose();
    super.dispose();
  }

  // ─── ACTIVITY PUBLISHING ─────────────────────────────────

  /// Publish current user activity to Firestore subcollection.
  void _publishActivity(String activityStatus) {
    if (currentUserId.isEmpty) return;
    appFirestore
        .collection('debates')
        .doc(widget.debateId)
        .collection('activity')
        .doc(currentUserId)
        .set({
      'status': activityStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((Object error) { debugPrint('Activity update unavailable: $error'); });

    // Auto-clear after 8 seconds of inactivity
    _activityClearTimer?.cancel();
    if (activityStatus.isNotEmpty) {
      _activityClearTimer = Timer(const Duration(seconds: 8), () {
        _clearMyActivity();
      });
    }
  }

  void _clearMyActivity() {
    if (currentUserId.isEmpty) return;
    appFirestore
        .collection('debates')
        .doc(widget.debateId)
        .collection('activity')
        .doc(currentUserId)
        .set({
      'status': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((Object error) { debugPrint('Activity update unavailable: $error'); });
  }

  /// Call from text input onChange — debounced at 500ms.
  void _onTypingChanged(String text) {
    _typingDebouncer?.cancel();
    if (text.trim().isNotEmpty) {
      _publishActivity('typing');
      _typingDebouncer = Timer(const Duration(milliseconds: 2000), () {
        _clearMyActivity();
      });
    } else {
      _clearMyActivity();
    }
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
                                uploadingMediaType: _pendingMediaType,
                                pendingMediaPath: _pendingMediaPath,
                                pendingMediaRequestId: _pendingMediaRequestId,
                                onPendingMediaConfirmed: _mediaConfirmed,
                                pendingMediaFailed: _pendingMediaFailed,
                                onRetryPendingMedia: _retryPendingMedia,
                                currentRoundIndex: roundIndex,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isFighter && status != 'finished') ...[
                      // ── Opponent Activity Indicator (animated slide-in) ──
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.6),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: anim,
                              curve: Curves.easeOut,
                            )),
                            child: child,
                          ),
                        ),
                        child: (_activeSpeakerActivity.isNotEmpty && !isMyTurn)
                            ? Padding(
                                key: ValueKey(_activeSpeakerActivity),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 4, 20, 0),
                                child: OpponentActivityIndicator(
                                  activity: _activeSpeakerActivity,
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('activity-hidden')),
                      ),
                      // ── Transitioning banner (shown at timer zero) ──
                      if (_isTransitioning)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 2, 20, 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.4,
                                  color: Colors.white38,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Смена раунда...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.38),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // ── Input Bar (dimmed when waiting for opponent) ──
                      AnimatedOpacity(
                        opacity: isMyTurn ? 1.0 : 0.52,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: DebateInputBar(
                            isMyTurn: isMyTurn,
                            canSendText: canSendText,
                            isSendingMessage: _isSendingMessage,
                            isUploading: _isUploadingMedia,
                            isRecording: _isRecording,
                            isRoundActive: isRoundActive,
                            isYielding: _isYieldingTurn,
                            recorderController: _recorderController,
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
                            onTypingChanged: _onTypingChanged,
                            uploadProgress: _batchUploadLabel,
                          ),
                        ),
                        ),
                      ),
                    ],
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

          // ── Round Transition Overlay ───────────────────────
          if (_roundOverlayMessage != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _overlayCtrl,
                      curve: Curves.easeOut,
                      reverseCurve: Curves.easeIn,
                    ),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.72, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _overlayCtrl,
                          curve: Curves.easeOutBack,
                          reverseCurve: Curves.easeIn,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 36,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xF00D111B),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFFFA500).withValues(alpha: 0.55),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFA500).withValues(alpha: 0.18),
                              blurRadius: 48,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          _roundOverlayMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ); // end Scaffold
  } // end build
} // end _DebateRoomScreenState
