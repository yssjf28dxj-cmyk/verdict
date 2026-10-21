import 'package:verdict/firestore_database.dart';
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/name_utils.dart';
import '../utils/rank_utils.dart';
import '../utils/style_utils.dart';
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
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  bool _isJoining = false;

  QueryDocumentSnapshot get doc => widget.doc;
  String get currentUid => widget.currentUid;
  bool get canEnter => widget.canEnter;

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
    await appFirestore
        .collection('debates')
        .doc(debateId)
        .update(patch);
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
      final fallback = {'internal', 'not-found', 'unavailable', 'unimplemented'};
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
      final fallback = {'internal', 'not-found', 'unavailable', 'unimplemented'};
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
                            style: const TextStyle(
                                fontWeight: FontWeight.w600))),
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
      final fallback = {'internal', 'not-found', 'unavailable', 'unimplemented'};
      if (!fallback.contains(e.code)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mapCallableError(l10n, e,
              fallbackMessage: l10n.sendRequestFailed)),
        ));
        return;
      }
      try {
        await appFirestore
            .collection('debates')
            .doc(debateId)
            .update({'accessRequests': FieldValue.arrayUnion([currentUid])});
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to join debate')));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // ─── UI helpers ──────────────────────────────────────────────────

  Widget _buildStatusBadge(String status) {
    if (_isLiveStatus(status)) return const LivePulseIndicator();
    if (_isWaitingStatus(status)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: VerdictStyle.accentGold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: VerdictStyle.accentGold.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: VerdictStyle.accentGold, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            const Text('WAITING',
                style: TextStyle(
                    color: VerdictStyle.accentGold,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.6)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: const Text('FINISHED',
          style: TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.6)),
    );
  }

  Widget _buildFighterAvatar({
    required String name,
    required Color color,
    required String heroTag,
    bool isEmpty = false,
    double rating = 0,
  }) {
    final rank = getRank(rating);
    return Expanded(
      child: Column(
        children: [
          Hero(
            tag: heroTag,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: isEmpty
                      ? color.withValues(alpha: 0.2)
                      : rank.color.withValues(alpha: 0.6),
                  width: 2,
                ),
                boxShadow:
                    (!isEmpty && (rank.key == 'master' || rank.key == 'grandmaster'))
                        ? [BoxShadow(color: rank.glowColor, blurRadius: 10, spreadRadius: 1)]
                        : null,
              ),
              child: isEmpty
                  ? Icon(Icons.person_add_alt_1,
                      color: color.withValues(alpha: 0.4), size: 22)
                  : Icon(Icons.person, color: color, size: 24),
            ),
          ),
          const SizedBox(height: 4),
          if (!isEmpty && rating > 0) ...[
            RankBadge(rating: rating, showLabel: false, iconSize: 12),
            const SizedBox(height: 2),
          ],
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
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
                        color: VerdictStyle.fighterBlue)),
                Expanded(
                    flex: rf,
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        color: VerdictStyle.fighterRed)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('$votes1',
                style: const TextStyle(
                    color: VerdictStyle.fighterBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11)),
            const Spacer(),
            Text('$votes2',
                style: const TextStyle(
                    color: VerdictStyle.fighterRed,
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
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.7)]),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.0)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = doc.data() as Map<String, dynamic>;

    final topic = _safeLocalizedText(
        (data['topic'] ?? '').toString(),
        _safeLocalizedText(l10n.topicNotSpecified, 'Topic not specified'));
    final fighter1 = firstNonEmptyName(
        [data['fighter1Name'], data['fighter1']], fallback: l10n.fighterOne);
    final fighter2 = firstNonEmptyName(
        [data['fighter2Name'], data['fighter2']], fallback: l10n.fighterTwo);
    final status = (data['status'] ?? 'live').toString();
    final votes1 = (data['votes1'] is num) ? (data['votes1'] as num).toInt() : 0;
    final votes2 = (data['votes2'] is num) ? (data['votes2'] as num).toInt() : 0;
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
    final currentRound =
        (data['currentRound'] is num) ? (data['currentRound'] as num).toInt() : 1;
    final totalRounds =
        (data['totalRounds'] is num) ? (data['totalRounds'] as num).toInt() : 1;
    final f1Rating =
        (data['fighter1Rating'] is num) ? (data['fighter1Rating'] as num).toDouble() : 0.0;
    final f2Rating =
        (data['fighter2Rating'] is num) ? (data['fighter2Rating'] as num).toDouble() : 0.0;

    final isLive = _isLiveStatus(status);
    final isWaiting = _isWaitingStatus(status);
    final hasFighter2 = (data['fighter2'] ?? '').toString().isNotEmpty;
    final isParticipant = currentUid.isNotEmpty &&
        (currentUid == (data['fighter1'] ?? '') ||
            currentUid == (data['fighter2'] ?? '') ||
            currentUid == creatorId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1A2035),
          border: Border.all(
            color: isLive
                ? VerdictStyle.fighterRed.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.06),
            width: isLive ? 1.5 : 1,
          ),
          boxShadow: isLive
              ? [
                  BoxShadow(
                    color: VerdictStyle.fighterRed.withValues(alpha: 0.12),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )
                ]
              : null,
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
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l10n.accessRestricted)));
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──
                  Row(
                    children: [
                      _buildStatusBadge(status),
                      const Spacer(),
                      if (isLive) ...[
                        Icon(Icons.visibility,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Text('$viewers',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.5))),
                        const SizedBox(width: 10),
                      ],
                      _metaChip(language),
                      const SizedBox(width: 4),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        _buildFighterAvatar(
                          name: fighter1,
                          color: VerdictStyle.fighterBlue,
                          heroTag: 'debate-${doc.id}-fighter-1',
                          rating: f1Rating,
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              const Text('VS',
                                  style: TextStyle(
                                      color: VerdictStyle.accentGold,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: 0.6)),
                              if (isLive) ...[
                                const SizedBox(height: 4),
                                Text(
                                    l10n.roundProgress(
                                        currentRound, totalRounds),
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white
                                            .withValues(alpha: 0.4))),
                              ],
                            ],
                          ),
                        ),
                        _buildFighterAvatar(
                          name: isWaiting && !hasFighter2 ? '?' : fighter2,
                          color: VerdictStyle.fighterRed,
                          heroTag: 'debate-${doc.id}-fighter-2',
                          isEmpty: isWaiting && !hasFighter2,
                          rating: f2Rating,
                        ),
                      ],
                    ),
                  ),

                  // ── Vote bar ──
                  if (!isWaiting) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _votePill(
                            color: VerdictStyle.fighterBlue, votes: votes1),
                        const SizedBox(width: 8),
                        _votePill(
                            color: VerdictStyle.fighterRed, votes: votes2),
                        const Spacer(),
                        if (visibility != 'public')
                          _metaChip(_prettyVisibility(l10n, visibility)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildVoteBar(votes1: votes1, votes2: votes2),
                  ],

                  // ── Action buttons ──
                  if (isWaiting && !isParticipant && canEnter) ...[
                    const SizedBox(height: 14),
                    _isJoining
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: VerdictStyle.fighterBlue),
                              ),
                            ),
                          )
                        : _buildActionButton(
                            label: l10n.joinAsFighter,
                            color: VerdictStyle.fighterBlue,
                            onTap: () => _joinAsFighter(context),
                          ),
                  ] else if (isWaiting && isParticipant) ...[
                    const SizedBox(height: 12),
                    _buildActionButton(
                      label: l10n.waitingForOpponent,
                      color: VerdictStyle.accentGold,
                      onTap: () => _navigateToDebate(context),
                    ),
                  ] else if (isLive && isParticipant && canEnter) ...[
                    const SizedBox(height: 14),
                    _buildActionButton(
                      label: '⚔️  CONTINUE DEBATE',
                      color: VerdictStyle.accentGold,
                      onTap: () => _navigateToDebate(context),
                    ),
                  ] else if (isLive && !isParticipant && canEnter) ...[
                    const SizedBox(height: 14),
                    _buildActionButton(
                      label: l10n.watchAndVote,
                      color: VerdictStyle.fighterRed,
                      onTap: () => _navigateToDebate(context),
                    ),
                  ],

                  // ── Access controls ──
                  if (!canEnter && visibility == 'request_only') ...[
                    const SizedBox(height: 12),
                    _buildActionButton(
                      label: alreadyRequested
                          ? _safeLocalizedText(l10n.requestSent, 'Request sent')
                          : _safeLocalizedText(
                              l10n.requestAccess, 'Request access'),
                      color: alreadyRequested
                          ? Colors.white24
                          : VerdictStyle.accentGold,
                      onTap: () =>
                          _requestAccess(context, doc.id, alreadyRequested),
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
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: VerdictStyle.fighterBlue.withValues(alpha: 0.1),
                          border: Border.all(
                              color: VerdictStyle.fighterBlue
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '${_safeLocalizedText(l10n.accessRequestsCountPrefix, 'Access requests')}: ${accessRequests.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: VerdictStyle.fighterBlue,
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
    );
  }
}
