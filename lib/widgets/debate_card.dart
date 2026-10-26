import 'package:verdict/firebase_session.dart';
import 'package:verdict/firestore_database.dart';
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/name_utils.dart';
import '../utils/rank_utils.dart';
import '../utils/arena_theme.dart';
import '../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

/// A card widget displaying a single debate in the home feed.
///
/// Extracted from home_screen.dart to reduce file complexity.
class DebateCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final String currentUid;
  final bool canEnter;

  const DebateCard({
    super.key,
    required this.doc,
    required this.currentUid,
    required this.canEnter,
  });

  @override
  State<DebateCard> createState() => _DebateCardState();
}

class _DebateCardState extends State<DebateCard> {
  final FirebaseFunctions _functions = appFunctions;
  bool _isJoining = false;
  bool _isCancelling = false;

  QueryDocumentSnapshot get doc => widget.doc;
  String get currentUid => widget.currentUid;
  bool get canEnter => widget.canEnter;

  Future<void> _cancelChallenge() async {
    if (_isCancelling) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.cancelChallengeTitle),
        content: Text(l10n.cancelChallengeConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.cancelChallenge),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isCancelling) return;
    setState(() => _isCancelling = true);
    try {
      await _functions
          .httpsCallable(
        'cancelDebateChallenge',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      )
          .call({'debateId': doc.id});
      // The feed stream removes the cancelled card. No direct client deletion.
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mapCallableError(l10n, error,
            fallbackMessage: l10n.cancelChallengeFailed)),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelChallengeFailed)),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  String _safeLocalizedText(String raw, String fallback) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.toUpperCase() == 'NOT_FOUND') {
      return fallback;
    }
    return normalized;
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  bool _isLiveStatus(String status) {
    final s = status.toLowerCase();
    return s == 'live' || s == 'active' || s.startsWith('round');
  }

  bool _isWaitingStatus(String status) => status.toLowerCase() == 'waiting';

  Future<void> _moderateAccessViaFallback({
    required String debateId,
    required String targetUid,
    required bool approve,
  }) async {
    final patch = <String, dynamic>{
      'accessRequests': FieldValue.arrayRemove([targetUid]),
    };
    if (approve) {
      patch['accessApprovedUserIds'] = FieldValue.arrayUnion([targetUid]);
    }
    await appFirestore.collection('debates').doc(debateId).update(patch);
  }

  Future<void> _approveAccess({
    required BuildContext context,
    required String debateId,
    required String targetUid,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _functions.httpsCallable('moderateAccessRequest').call({
        'debateId': debateId,
        'targetUid': targetUid,
        'action': 'approve',
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.accessApproved)));
    } on FirebaseFunctionsException catch (e) {
      final fallback = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented'
      };
      if (!fallback.contains(e.code)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mapCallableError(l10n, e,
              fallbackMessage: l10n.approveAccessFailed)),
        ));
        return;
      }
      try {
        await _moderateAccessViaFallback(
            debateId: debateId, targetUid: targetUid, approve: true);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.accessApproved)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.approveAccessFailed)));
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.approveAccessFailed)));
    }
  }

  Future<void> _rejectAccess({
    required BuildContext context,
    required String debateId,
    required String targetUid,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _functions.httpsCallable('moderateAccessRequest').call({
        'debateId': debateId,
        'targetUid': targetUid,
        'action': 'reject',
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.requestRejected)));
    } on FirebaseFunctionsException catch (e) {
      final fallback = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented'
      };
      if (!fallback.contains(e.code)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mapCallableError(l10n, e,
              fallbackMessage: l10n.rejectRequestFailed)),
        ));
        return;
      }
      try {
        await _moderateAccessViaFallback(
            debateId: debateId, targetUid: targetUid, approve: false);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.requestRejected)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.rejectRequestFailed)));
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.rejectRequestFailed)));
    }
  }

  Future<void> _showAccessRequestsDialog({
    required BuildContext context,
    required String debateId,
    required List<String> requests,
  }) async {
    if (requests.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.accessRequestsTitle),
          content: SizedBox(
            width: 360,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: requests.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (ctx, i) {
                final uid = requests[i];
                return Row(
                  children: [
                    Expanded(
                        child: Text(uid,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                    IconButton(
                      tooltip: l10n.reject,
                      onPressed: () => _rejectAccess(
                          context: dialogContext,
                          debateId: debateId,
                          targetUid: uid),
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                    ),
                    IconButton(
                      tooltip: l10n.approve,
                      onPressed: () => _approveAccess(
                          context: dialogContext,
                          debateId: debateId,
                          targetUid: uid),
                      icon: const Icon(Icons.check, color: Colors.green),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _requestAccess(
      BuildContext context, String debateId, bool alreadyRequested) async {
    final l10n = AppLocalizations.of(context)!;
    if (currentUid.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.loginToRequestAccess)));
      return;
    }
    if (alreadyRequested) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.requestAlreadySent)));
      return;
    }
    try {
      await _functions
          .httpsCallable('requestDebateAccess')
          .call({'debateId': debateId});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.accessRequestSent)));
    } on FirebaseFunctionsException catch (e) {
      final fallback = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented'
      };
      if (!fallback.contains(e.code)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mapCallableError(l10n, e,
              fallbackMessage: l10n.sendRequestFailed)),
        ));
        return;
      }
      try {
        await appFirestore.collection('debates').doc(debateId).update({
          'accessRequests': FieldValue.arrayUnion([currentUid])
        });
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.accessRequestSent)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.sendRequestFailed)));
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.sendRequestFailed)));
    }
  }

  void _navigateToDebate(BuildContext context) {
    context.push('/debate/${doc.id}');
  }

  Future<void> _joinAsFighter(BuildContext context) async {
    if (_isJoining) return;
    HapticFeedback.mediumImpact();
    setState(() => _isJoining = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final callable = _functions.httpsCallable(
        'acceptDebateInvite',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );
      await callable.call({'debateId': doc.id});
      if (!context.mounted) return;
      _navigateToDebate(context);
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'already-exists' || e.code == 'failed-precondition') {
        _navigateToDebate(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mapCallableError(l10n, e,
            fallbackMessage: 'Failed to join debate')),
      ));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to join debate')));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // ─── UI helpers ──────────────────────────────────────────────────

  Widget _buildStatusBadge(String status) {
    final l10n = AppLocalizations.of(context)!;
    final live = _isLiveStatus(status);
    final waiting = _isWaitingStatus(status);
    final color = live
        ? ArenaTheme.red
        : waiting
            ? ArenaTheme.accent
            : Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text(
          live
              ? l10n.liveStatus
              : waiting
                  ? l10n.waitingStatus
                  : l10n.finishedStatus,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildFighterAvatar({
    required String name,
    required Color color,
    required String heroTag,
    bool isEmpty = false,
    double rating = 0,
  }) {
    return Expanded(
      child: Column(
        children: [
          Hero(
            tag: heroTag,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: isEmpty
                  ? Icon(Icons.person_add_alt_1,
                      color: color.withValues(alpha: 0.4), size: 22)
                  : Icon(Icons.person, color: color, size: 20),
            ),
          ),
          const SizedBox(height: 4),
          if (!isEmpty && rating > 0) ...[
            RankBadge(rating: rating, showLabel: false, iconSize: 12),
            const SizedBox(height: 2),
          ],
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isEmpty ? Colors.white30 : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 0.3)),
      );

  Widget _votePill({required Color color, required int votes}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.how_to_vote, size: 12, color: color),
            const SizedBox(width: 4),
            Text('$votes',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: color, fontSize: 11)),
          ],
        ),
      );

  Widget _buildVoteBar({required int votes1, required int votes2}) {
    final total = votes1 + votes2;
    final lf = total == 0 ? 1 : votes1;
    final rf = total == 0 ? 1 : votes2;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 8,
            color: Colors.white.withValues(alpha: 0.06),
            child: Row(
              children: [
                Expanded(
                    flex: lf,
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        color: ArenaTheme.blue)),
                Expanded(
                    flex: rf,
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        color: ArenaTheme.red)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('$votes1',
                style: const TextStyle(
                    color: ArenaTheme.blue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11)),
            const Spacer(),
            Text('$votes2',
                style: const TextStyle(
                    color: ArenaTheme.red,
                    fontWeight: FontWeight.w800,
                    fontSize: 11)),
          ],
        ),
      ],
    );
  }

  String _prettyVisibility(AppLocalizations l10n, String mode) =>
      switch (mode) {
        'private' => l10n.privateMode,
        'request_only' => l10n.requestOnly,
        _ => l10n.publicMode,
      };

  String _prettyRegion(AppLocalizations l10n, String region) =>
      switch (region) {
        'cis' => l10n.regionCis,
        'mena' => l10n.regionMena,
        'europe_africa' => l10n.regionEuAf,
        _ => l10n.regionGlobal,
      };

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color.withValues(alpha: 0.14),
              foregroundColor: color,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onPressed: onTap,
            child: Text(label, textAlign: TextAlign.center),
          ));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = doc.data() as Map<String, dynamic>;

    final topic = _safeLocalizedText((data['topic'] ?? '').toString(),
        _safeLocalizedText(l10n.topicNotSpecified, 'Topic not specified'));
    final fighter1 = firstNonEmptyName([data['fighter1Name'], data['fighter1']],
        fallback: l10n.fighterOne);
    final fighter2 = firstNonEmptyName([data['fighter2Name'], data['fighter2']],
        fallback: l10n.fighterTwo);
    final status = (data['status'] ?? 'live').toString();
    final votes1 =
        (data['votes1'] is num) ? (data['votes1'] as num).toInt() : 0;
    final votes2 =
        (data['votes2'] is num) ? (data['votes2'] as num).toInt() : 0;
    final viewers =
        (data['viewerCount'] is num) ? (data['viewerCount'] as num).toInt() : 0;
    final visibility =
        (data['visibilityMode'] ?? 'public').toString().toLowerCase();
    final language = (data['languageCode'] ?? 'ru').toString().toUpperCase();
    final region = (data['region'] ?? 'global').toString().toLowerCase();
    final creatorId = (data['creatorId'] ?? '').toString();
    final accessRequests = _stringList(data['accessRequests']);
    final alreadyRequested = accessRequests.contains(currentUid);
    final isCreator = currentUid.isNotEmpty && currentUid == creatorId;
    final currentRound = (data['roundIndex'] is num)
        ? (data['roundIndex'] as num).toInt()
        : (data['currentRound'] is num)
            ? (data['currentRound'] as num).toInt()
            : 1;
    final totalRounds =
        (data['totalRounds'] is num) ? (data['totalRounds'] as num).toInt() : 1;
    final f1Rating = (data['fighter1Rating'] is num)
        ? (data['fighter1Rating'] as num).toDouble()
        : 0.0;
    final f2Rating = (data['fighter2Rating'] is num)
        ? (data['fighter2Rating'] as num).toDouble()
        : 0.0;

    final isLive = _isLiveStatus(status);
    final isWaiting = _isWaitingStatus(status);
    final hasFighter2 = (data['fighter2'] ?? '').toString().isNotEmpty;
    final isParticipant = currentUid.isNotEmpty &&
        (currentUid == (data['fighter1'] ?? '') ||
            currentUid == (data['fighter2'] ?? '') ||
            currentUid == creatorId);

    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: ArenaTheme.surface,
                  border: Border.all(color: ArenaTheme.border),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      if (canEnter) {
                        _navigateToDebate(context);
                        return;
                      }
                      if (visibility == 'request_only') {
                        _requestAccess(context, doc.id, alreadyRequested);
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.accessRestricted)));
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Header ──
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildStatusBadge(status),
                              if (isLive) _metaChip(l10n.viewersCount(viewers)),
                              _metaChip(language),
                              _metaChip(_prettyRegion(l10n, region)),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // ── Topic ──
                          Text(topic,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.3)),
                          const SizedBox(height: 14),

                          // ── Fighters ──
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                _buildFighterAvatar(
                                  name: fighter1,
                                  color: ArenaTheme.blue,
                                  heroTag: 'debate-${doc.id}-fighter-1',
                                  rating: f1Rating,
                                ),
                                const Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 8),
                                  child: Column(
                                    children: [
                                      Text('VS',
                                          style: TextStyle(
                                              color: ArenaTheme.accent,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              letterSpacing: 0.6)),
                                    ],
                                  ),
                                ),
                                _buildFighterAvatar(
                                  name: isWaiting && !hasFighter2
                                      ? '?'
                                      : fighter2,
                                  color: ArenaTheme.red,
                                  heroTag: 'debate-${doc.id}-fighter-2',
                                  isEmpty: isWaiting && !hasFighter2,
                                  rating: f2Rating,
                                ),
                              ],
                            ),
                          ),

                          if (isLive)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                  l10n.roundProgress(currentRound, totalRounds),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ),

                          // ── Vote bar ──
                          if (!isWaiting) ...[
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              _votePill(color: ArenaTheme.blue, votes: votes1),
                              _votePill(color: ArenaTheme.red, votes: votes2),
                              if (visibility != 'public')
                                _metaChip(_prettyVisibility(l10n, visibility)),
                            ]),
                            const SizedBox(height: 10),
                            _buildVoteBar(votes1: votes1, votes2: votes2),
                          ],

                          // ── Action buttons ──
                          if (isWaiting && !isParticipant && canEnter) ...[
                            const SizedBox(height: 14),
                            _isJoining
                                ? const Center(
                                    child: Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: ArenaTheme.blue),
                                      ),
                                    ),
                                  )
                                : _buildActionButton(
                                    label: l10n.joinAsFighter,
                                    color: ArenaTheme.blue,
                                    onTap: () => _joinAsFighter(context),
                                  ),
                          ] else if (isWaiting && isParticipant) ...[
                            const SizedBox(height: 12),
                            _buildActionButton(
                              label: l10n.waitingForOpponent,
                              color: ArenaTheme.accent,
                              onTap: () => _navigateToDebate(context),
                            ),
                            if (isCreator) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed:
                                    _isCancelling ? null : _cancelChallenge,
                                icon: _isCancelling
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.close),
                                label: Text(l10n.cancelChallenge),
                              ),
                            ],
                          ] else if (isLive && isParticipant && canEnter) ...[
                            const SizedBox(height: 14),
                            _buildActionButton(
                              label: l10n.continueDebate,
                              color: ArenaTheme.accent,
                              onTap: () => _navigateToDebate(context),
                            ),
                          ] else if (isLive && !isParticipant && canEnter) ...[
                            const SizedBox(height: 14),
                            _buildActionButton(
                              label: l10n.watchAndVote,
                              color: ArenaTheme.red,
                              onTap: () => _navigateToDebate(context),
                            ),
                          ],

                          // ── Access controls ──
                          if (!canEnter && visibility == 'request_only') ...[
                            const SizedBox(height: 12),
                            _buildActionButton(
                              label: alreadyRequested
                                  ? _safeLocalizedText(
                                      l10n.requestSent, 'Request sent')
                                  : _safeLocalizedText(
                                      l10n.requestAccess, 'Request access'),
                              color: alreadyRequested
                                  ? Colors.white24
                                  : ArenaTheme.accent,
                              onTap: () => _requestAccess(
                                  context, doc.id, alreadyRequested),
                            ),
                          ],
                          if (isCreator && accessRequests.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _showAccessRequestsDialog(
                                  context: context,
                                  debateId: doc.id,
                                  requests: accessRequests),
                              child: Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: ArenaTheme.blue.withValues(alpha: 0.1),
                                  border: Border.all(
                                      color: ArenaTheme.blue
                                          .withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  '${_safeLocalizedText(l10n.accessRequestsCountPrefix, 'Access requests')}: ${accessRequests.length}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: ArenaTheme.blue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )));
  }
}
