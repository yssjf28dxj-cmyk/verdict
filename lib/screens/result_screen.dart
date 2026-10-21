import 'package:verdict/firestore_database.dart';
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../painters/chat_pattern_painter.dart';
import '../services/sound_service.dart';
import '../utils/name_utils.dart';
import '../utils/style_utils.dart';
import '../widgets/ai_result_card.dart';
import 'package:go_router/go_router.dart';

class ResultScreen extends StatefulWidget {
  final String debateId;

  const ResultScreen({super.key, required this.debateId});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _debateFuture;
  bool _didPlayOutcomeCue = false;

  // ── AI Judge state ────────────────────────────────────────────────────────
  final ValueNotifier<Map<String, dynamic>?> _aiResult = ValueNotifier(null);
  final ValueNotifier<bool> _aiLoading = ValueNotifier(false);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _aiSub;
  Timer? _aiTimeoutTimer;
  bool _didRequestAi = false;

  @override
  void initState() {
    super.initState();
    _debateFuture = appFirestore
        .collection('debates')
        .doc(widget.debateId)
        .get();
  }

  @override
  void dispose() {
    _aiTimeoutTimer?.cancel();
    _aiResult.dispose();
    _aiLoading.dispose();
    _aiSub?.cancel();
    super.dispose();
  }

  // Idempotent: calls finalizeBattle once, then streams for the written result.
  void _maybeRequestAiVerdict(Map<String, dynamic> data) {
    if (_didRequestAi) return;
    _didRequestAi = true;

    // Already judged — show immediately without calling CF.
    final existing = data['aiResult'];
    if (existing is Map) {
      _aiResult.value = Map<String, dynamic>.from(existing);
      return;
    }

    _aiLoading.value = true;

    // Fire-and-forget — stream catches the Firestore write regardless of
    // whether the CF response arrives (handles network drops cleanly).
    unawaited(() async {
      try {
        await FirebaseFunctions.instance
            .httpsCallable('finalizeBattle')
            .call({'debateId': widget.debateId});
      } catch (e) {
        // FINALIZE_ALREADY_JUDGED is expected on re-entry — stream handles it.
        debugPrint('[AI Judge] finalizeBattle: $e');
      }
    }());

    // Stream on the debate doc — stops as soon as aiResult appears.
    _aiSub = appFirestore
        .collection('debates')
        .doc(widget.debateId)
        .snapshots()
        .listen((snap) {
      final d = snap.data();
      if (d == null) return;
      final aiData = d['aiResult'];
      if (aiData is Map) {
        _aiTimeoutTimer?.cancel();
        if (mounted) {
          _aiResult.value = Map<String, dynamic>.from(aiData);
          _aiLoading.value = false;
        }
        _aiSub?.cancel();
      }
    });

    // Fallback: if AI result doesn't arrive within 15s, show error card.
    _aiTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_aiResult.value != null) return; // already resolved
      _aiSub?.cancel();
      _aiResult.value = {'error': true, 'reason': 'timeout'};
      _aiLoading.value = false;
    });
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  void _playOutcomeCue(Map<String, dynamic> data) {
    if (_didPlayOutcomeCue) return;
    _didPlayOutcomeCue = true;

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final fighter1Id = (data['fighter1'] ?? '').toString();
    final fighter2Id = (data['fighter2'] ?? '').toString();
    final votes1 = _asInt(data['votes1']);
    final votes2 = _asInt(data['votes2']);

    if (votes1 == votes2) {
      HapticFeedback.selectionClick();
      return;
    }

    final isParticipant = currentUid == fighter1Id || currentUid == fighter2Id;
    if (!isParticipant) return;

    final fighter1Won = votes1 > votes2;
    final didWin = (currentUid == fighter1Id && fighter1Won) ||
        (currentUid == fighter2Id && !fighter1Won);

    HapticFeedback.heavyImpact();
    SoundService.instance.play(didWin ? SFX.victory : SFX.defeat);
  }

  Widget _buildHeroAvatar({
    required String heroTag,
    required Color color,
    required String name,
  }) {
    return Column(
      children: [
        Hero(
          tag: heroTag,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.28),
                  color.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                color: color.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            child: Icon(Icons.person, color: color, size: 34),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 110,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoteBar({
    required int votes1,
    required int votes2,
  }) {
    final totalVotes = votes1 + votes2;
    final leftFlex = totalVotes == 0 ? 1 : votes1;
    final rightFlex = totalVotes == 0 ? 1 : votes2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 12,
        color: Colors.white.withValues(alpha: 0.08),
        child: Row(
          children: [
            Expanded(
              flex: leftFlex,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                color: VerdictStyle.fighterBlue,
              ),
            ),
            Expanded(
              flex: rightFlex,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                color: VerdictStyle.fighterRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1320),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1320),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          l10n.appTitle,
          style: const TextStyle(
            color: Color(0xFFFFA500),
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: _debateFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFA500)),
                );
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Center(
                  child: Text(
                    l10n.battleDataNotFound,
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }

              final rawData = snapshot.data!.data();
              if (rawData == null) {
                return Center(
                  child: Text(
                    l10n.battleDataNotFound,
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }

              final data = rawData;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (!_didPlayOutcomeCue) _playOutcomeCue(data);
                _maybeRequestAiVerdict(data);
              });

              final topic = firstNonEmptyName(
                [data['topic']],
                fallback: l10n.unknownTopic,
              );
              final fighter1Name = firstNonEmptyName(
                [data['fighter1Name'], data['fighter1']],
                fallback: l10n.fighterOne,
              );
              final fighter2Name = firstNonEmptyName(
                [data['fighter2Name'], data['fighter2']],
                fallback: l10n.fighterTwo,
              );
              final votes1 = _asInt(data['votes1']);
              final votes2 = _asInt(data['votes2']);

              String winnerName = l10n.draw;
              Color winnerColor = Colors.grey;
              if (votes1 > votes2) {
                winnerName = '${l10n.victoryPrefix}: $fighter1Name';
                winnerColor = VerdictStyle.fighterBlue;
              } else if (votes2 > votes1) {
                winnerName = '${l10n.victoryPrefix}: $fighter2Name';
                winnerColor = VerdictStyle.fighterRed;
              }

              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.debateTopicLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            topic,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 36),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildHeroAvatar(
                                heroTag: 'debate-${widget.debateId}-fighter-1',
                                color: VerdictStyle.fighterBlue,
                                name: fighter1Name,
                              ),
                              Text(
                                l10n.versusLabel,
                                style: const TextStyle(
                                  color: Color(0xFFFFA500),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              _buildHeroAvatar(
                                heroTag: 'debate-${widget.debateId}-fighter-2',
                                color: VerdictStyle.fighterRed,
                                name: fighter2Name,
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 30,
                                  horizontal: 20,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x661D2233),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: winnerColor.withValues(alpha: 0.5),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: winnerColor.withValues(alpha: 0.2),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.emoji_events,
                                      size: 60,
                                      color: winnerColor,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      winnerName,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: winnerColor,
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          GlassCard(
                            borderRadius: BorderRadius.circular(24),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildStatCol(
                                        fighter1Name,
                                        votes1.toString(),
                                        VerdictStyle.fighterBlue,
                                        context,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildStatCol(
                                        fighter2Name,
                                        votes2.toString(),
                                        VerdictStyle.fighterRed,
                                        context,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                _buildVoteBar(votes1: votes1, votes2: votes2),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<bool>(
                            valueListenable: _aiLoading,
                            builder: (context, loading, _) {
                              if (!loading) return const SizedBox.shrink();
                              return const GlassCard(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Color(0xFFFFA500),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Судья анализирует...',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          ValueListenableBuilder<Map<String, dynamic>?>(
                            valueListenable: _aiResult,
                            builder: (context, aiResult, _) {
                              if (aiResult == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: AiResultCard(
                                  aiResult: aiResult,
                                  fighter1Name: fighter1Name,
                                  fighter2Name: fighter2Name,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () {
                                context.go('/');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: VerdictStyle.accentGold,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: Text(
                                l10n.backToHome,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCol(
    String name,
    String votes,
    Color color,
    BuildContext context,
  ) {
    return Column(
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$votes ${AppLocalizations.of(context)!.votesLabel}',
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
