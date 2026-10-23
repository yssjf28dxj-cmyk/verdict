import 'package:verdict/firebase_session.dart';
import 'package:verdict/firestore_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import '../utils/invitation_links.dart';
import '../utils/compact_notice.dart';
import '../painters/chat_pattern_painter.dart';
import '../services/pending_debate_service.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

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
  bool _isCopyingInvitation = false;
  bool _watchingRegistered = false;
  int? _proposedDurationSeconds;
  int? _proposedTotalRounds;
  final FirebaseFunctions _functions = appFunctions;

  @override
  void initState() {
    super.initState();
    // Register the background watcher only after a permitted, existing
    // document is received. A link alone never establishes read access.
  }

  Future<void> _copyInvitation() async {
    if (_isCopyingInvitation || !invitationsEnabled) return;
    setState(() => _isCopyingInvitation = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      await Clipboard.setData(ClipboardData(text: testInvitationLink(widget.debateId).toString()));
      if (mounted) showCompactNotice(context, l10n.invitationCopied);
    } catch (_) {
      if (mounted) showCompactNotice(context, l10n.invitationCopyFailed);
    } finally {
      if (mounted) setState(() => _isCopyingInvitation = false);
    }
  }

  Widget _unavailable(AppLocalizations l10n, {bool retry = false}) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Text(retry ? l10n.invitationLoadFailed : l10n.invitationUnavailable, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (retry) FilledButton(onPressed: () => setState(() {}), child: Text(l10n.invitationRetry)),
        TextButton(onPressed: () => context.go('/home'), child: Text(l10n.mainTab)),
      ])));

  @override
  void dispose() {
    super.dispose();
  }

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
    // BUG FIX: was calling context.pop() BEFORE the actual API call.
    // Now we properly call the backend first, then navigate out.
    final callable = _functions.httpsCallable('cancelDebateChallenge');
    final payload = {'debateId': widget.debateId};
    setState(() => _isCancelling = true);
    try {
      await callable.call(payload);
      // Stop background watching since we cancelled
      PendingDebateService.instance.stopWatching();
      if (!mounted) return;
      context.pop();
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
        PendingDebateService.instance.stopWatching();
        if (!mounted) return;
        context.pop();
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
    final payload = <String, dynamic>{
      'debateId': widget.debateId,
      if (_proposedDurationSeconds != null)
        'proposedRoundDurationSeconds': _proposedDurationSeconds,
      if (_proposedTotalRounds != null)
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

  void _minimizeLobby() {
    // Keep the PendingDebateService watching in the background,
    // and just go back to the previous screen (home feed).
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
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
      // Stop background service since we are navigating directly
      PendingDebateService.instance.stopWatching();
      context.replace('/debate/${widget.debateId}');
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
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          tooltip: 'Minimize — keep waiting in background',
          onPressed: _minimizeLobby,
        ),
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
            stream: appFirestore
                .collection('debates')
                .doc(widget.debateId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                final denied = error is FirebaseException && ['permission-denied', 'not-found'].contains(error.code);
                return _unavailable(l10n, retry: !denied);
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFB74D)),
                );
              }
              if (!snapshot.data!.exists) return _unavailable(l10n);

              final data = snapshot.data!.data() ?? {};
              final status = data['status'] ?? 'waiting';
              if (status == 'cancelled' || status == 'deleted') return _unavailable(l10n);
              if (status == 'finished') {
                if (!_navigated) {
                  _navigated = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) context.replace('/result/${widget.debateId}');
                  });
                }
                return const Center(child: CircularProgressIndicator());
              }
              final topic = data['topic'] ?? l10n.loadingTopic;

              if (status == 'waiting' && !_watchingRegistered) {
                _watchingRegistered = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) PendingDebateService.instance.startWatching(widget.debateId, topic: topic.toString());
                });
              }

              final currentUid = appAuth.currentUser?.uid ?? '';
              final invitedUserId = (data['invitedUserId'] ?? '').toString();
              final fighter1 = (data['fighter1'] ?? '').toString();
              final rawCreator = (data['creatorId'] ?? '').toString();
              final creatorId = rawCreator.isEmpty ? fighter1 : rawCreator;
              final isCreator = currentUid.isNotEmpty && currentUid == creatorId;
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
              final canAcceptInvite =
                  canAcceptDirectInvite || canAcceptOpenWaiting;
              final shouldEnterDebate = status == 'active' || status == 'live';

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
                          if (isCreator && status == 'waiting' && invitationsEnabled) ...[
                            OutlinedButton.icon(onPressed: _isCopyingInvitation ? null : _copyInvitation,
                              icon: const Icon(Icons.link), label: Text(l10n.invitationCopy)),
                            const SizedBox(height: 8), Text(l10n.invitationAccessHint, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                          ],
                          if (isCreator && status == 'waiting')
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
