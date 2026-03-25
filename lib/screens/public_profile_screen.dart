import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/debate_history_item.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/rank_utils.dart';
import '../utils/style_utils.dart';
import '../utils/debate_error_mapper.dart';
import 'lobby_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({
    super.key,
    required this.uid,
    required this.publicId,
    required this.name,
  });

  final String uid;
  final String publicId;
  final String name;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _loading = true;
  bool _isChallengeSending = false;
  int _wins = 0;
  int _losses = 0;
  int _draws = 0;
  int _totalDebates = 0;
  double _rating = 0;
  double _reputation = 0;
  double _viewerScore = 0;
  String _style = 'Balanced';
  List<DebateHistoryItem> _recentDebates = const [];

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final userData = userDoc.data() ?? {};

      final debateSnapshots = await Future.wait([
        FirebaseFirestore.instance
            .collection('debates')
            .where('fighter1', isEqualTo: widget.uid)
            .limit(20)
            .get(),
        FirebaseFirestore.instance
            .collection('debates')
            .where('fighter2', isEqualTo: widget.uid)
            .limit(20)
            .get(),
      ]);

      final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snapshot in debateSnapshots) {
        for (final doc in snapshot.docs) {
          merged[doc.id] = doc;
        }
      }

      final history = merged.values.map((doc) {
        final data = doc.data();
        final fighter1 = (data['fighter1'] ?? '').toString();
        final fighter2 = (data['fighter2'] ?? '').toString();
        final fighter1Name = (data['fighter1Name'] ?? '').toString().trim();
        final fighter2Name = (data['fighter2Name'] ?? '').toString().trim();
        final isFighter1 = fighter1 == widget.uid;
        final opponentUid = isFighter1 ? fighter2 : fighter1;
        final opponentName = isFighter1 ? fighter2Name : fighter1Name;
        final winner = (data['winner'] ?? '').toString();
        final status = (data['status'] ?? '').toString();
        final topic = (data['topic'] ?? '').toString().trim();
        final ts = data['createdAt'];
        final createdAt = ts is Timestamp ? ts.toDate() : null;

        String outcomeLabel;
        if (winner == 'draw') {
          outcomeLabel = 'DRAW';
        } else if ((winner == 'fighter1' && isFighter1) ||
            (winner == 'fighter2' && !isFighter1)) {
          outcomeLabel = 'WIN';
        } else if ((winner == 'fighter1' && !isFighter1) ||
            (winner == 'fighter2' && isFighter1)) {
          outcomeLabel = 'LOSS';
        } else {
          outcomeLabel = status == 'finished' ? 'FINISHED' : 'LIVE';
        }

        return DebateHistoryItem(
          debateId: doc.id,
          topic: topic.isNotEmpty ? topic : 'Unknown topic',
          status: status,
          opponentLabel: opponentName.isNotEmpty
              ? opponentName
              : (opponentUid.isNotEmpty ? opponentUid : 'Unknown opponent'),
          outcomeLabel: outcomeLabel,
          createdAt: createdAt,
        );
      }).toList()
        ..sort((a, b) {
          final aa = a.createdAt;
          final bb = b.createdAt;
          if (aa == null && bb == null) return 0;
          if (aa == null) return 1;
          if (bb == null) return -1;
          return bb.compareTo(aa);
        });

      if (!mounted || _disposed) return;
      setState(() {
        _wins = (userData['wins'] as int?) ?? 0;
        _losses = (userData['losses'] as int?) ?? 0;
        _draws = (userData['draws'] as int?) ?? 0;
        _totalDebates = (userData['totalDebates'] as int?) ?? 0;
        _rating = (userData['rating'] as num?)?.toDouble() ?? 0;
        _reputation = (userData['reputation'] as num?)?.toDouble() ?? 0;
        _viewerScore = (userData['viewerScore'] as num?)?.toDouble() ?? 0;
        _style = (userData['debateStyle'] ?? 'Balanced').toString();
        _recentDebates = history.take(5).toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted || _disposed) return;
      setState(() {
        _loading = false;
      });
    }
  }

  double get _winRate {
    if (_totalDebates <= 0) return 0;
    return ((_wins + (_draws * 0.5)) / _totalDebates) * 100;
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '--';
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Color _outcomeColor(String outcome) {
    switch (outcome) {
      case 'WIN':
        return const Color(0xFF4CAF50);
      case 'LOSS':
        return const Color(0xFFFF6B6B);
      case 'DRAW':
        return const Color(0xFFFFB74D);
      default:
        return Colors.white70;
    }
  }

  String _extractDebateId(dynamic payload) {
    if (payload is Map) {
      final direct = (payload['debateId'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;
      final nested = payload['data'];
      if (nested is Map) {
        return (nested['debateId'] ?? '').toString().trim();
      }
    }
    return '';
  }

  Future<void> _challengeToDebate() async {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authRequired)),
      );
      return;
    }
    if (currentUser.uid == widget.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cannotAcceptOwnChallenge)),
      );
      return;
    }

    final localeCode = Localizations.localeOf(context).languageCode;
    final langCode = (localeCode == 'ru' || localeCode == 'en' || localeCode == 'ar')
        ? localeCode
        : 'ru';

    // Ask for topic
    final topicController = TextEditingController();
    final topic = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.directInvite),
          content: TextField(
            controller: topicController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.debateTopicLabel,
              hintText: l10n.enterTopic,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(topicController.text.trim()),
              child: Text(l10n.publishChallenge),
            ),
          ],
        );
      },
    );

    if (topic == null || topic.trim().length < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterTopicValidation)),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isChallengeSending = true);

    try {

      final callable = FirebaseFunctions.instance.httpsCallable(
        'createDebate',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );
      final result = await callable.call({
        'topic': topic.trim(),
        'durationSeconds': 180,
        'totalRounds': 3,
        'creationMode': 'direct_invite',
        'visibilityMode': 'private',
        'languageCode': langCode,
        'region': 'global',
        'invitedUserId': widget.uid,
      });

      final debateId = _extractDebateId(result.data);
      if (debateId.isEmpty) {
        throw Exception(l10n.serverNoDebateId);
      }

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LobbyScreen(debateId: debateId),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapCallableError(
            l10n,
            e,
            fallbackMessage: '${l10n.serverErrorPrefix}: ${e.code}',
          )),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorPrefix}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isChallengeSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rank = getRank(_rating);
    final langCode = Localizations.localeOf(context).languageCode;
    final isElite = rank.key == 'master' || rank.key == 'grandmaster';

    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'FIGHTER PROFILE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: VerdictStyle.accentGold,
            fontSize: 16,
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
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: VerdictStyle.accentGold))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  child: Column(
                    children: [
                      // ── HERO CARD ──────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              rank.color.withValues(alpha: 0.12),
                              const Color(0xFF1A2035),
                              rank.color.withValues(alpha: 0.06),
                            ],
                          ),
                          border: Border.all(
                            color: rank.color.withValues(alpha: isElite ? 0.5 : 0.2),
                            width: isElite ? 1.5 : 1,
                          ),
                          boxShadow: isElite
                              ? [
                                  BoxShadow(
                                    color: rank.glowColor,
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          children: [
                            // Avatar
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    rank.color.withValues(alpha: 0.3),
                                    rank.color.withValues(alpha: 0.08),
                                  ],
                                ),
                                border: Border.all(
                                  color: rank.color.withValues(alpha: 0.6),
                                  width: 3,
                                ),
                                boxShadow: isElite
                                    ? [
                                        BoxShadow(
                                          color: rank.glowColor,
                                          blurRadius: 20,
                                          spreadRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                Icons.person,
                                size: 46,
                                color: rank.color.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Name
                            Text(
                              (widget.name.isNotEmpty ? widget.name : widget.publicId)
                                  .toUpperCase(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Rank badge
                            RankBadge(rating: _rating, iconSize: 16, fontSize: 11),
                            const SizedBox(height: 8),

                            // Public ID
                            Text(
                              widget.publicId,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Style
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.psychology_alt_outlined,
                                    size: 14,
                                    color: VerdictStyle.accentGold.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${l10n.styleLabel}: $_style',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── CHALLENGE BUTTON ───────────────────
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isChallengeSending ? null : _challengeToDebate,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  VerdictStyle.fighterRed,
                                  VerdictStyle.fighterRed.withValues(alpha: 0.7),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: VerdictStyle.fighterRed.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _isChallengeSending
                                ? const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.sports_mma,
                                          color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.directInvite.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── BOXING W/L/D ───────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: const Color(0xFF1A2035),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _boxingStat('$_wins', l10n.wins,
                                    const Color(0xFF4CAF50)),
                                Container(
                                  width: 1,
                                  height: 50,
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                                _boxingStat('$_losses', l10n.losses,
                                    const Color(0xFFFF6B6B)),
                                Container(
                                  width: 1,
                                  height: 50,
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                                _boxingStat('$_draws', l10n.draws,
                                    const Color(0xFFFFB74D)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            // Win rate bar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l10n.winRate,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${_winRate.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (_winRate / 100).clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _winRate >= 60
                                      ? const Color(0xFF4CAF50)
                                      : _winRate >= 40
                                          ? VerdictStyle.accentGold
                                          : const Color(0xFFFF6B6B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── RATING CARD ────────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: const Color(0xFF1A2035),
                          border: Border.all(
                              color: rank.color.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(rank.icon, color: rank.color, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.rating,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _rating.toStringAsFixed(0),
                                  style: TextStyle(
                                    color: rank.color,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: rank.progress(_rating),
                                minHeight: 8,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.08),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(rank.color),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                rank.localizedTitle(langCode),
                                style: TextStyle(
                                  color: rank.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── STATS ROW ──────────────────────────
                      Row(
                        children: [
                          _miniStat(Icons.bolt, l10n.battles,
                              '$_totalDebates', VerdictStyle.fighterRed),
                          const SizedBox(width: 8),
                          _miniStat(
                              Icons.shield,
                              l10n.reputation,
                              _reputation.toStringAsFixed(0),
                              const Color(0xFF4DB6AC)),
                          const SizedBox(width: 8),
                          _miniStat(
                              Icons.groups_rounded,
                              l10n.audience,
                              _viewerScore.toStringAsFixed(0),
                              const Color(0xFF64B5F6)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── RECENT DEBATES ─────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: const Color(0xFF1A2035),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.recentDebates,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_recentDebates.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text(
                                    l10n.noDebatesYet,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                              )
                            else
                              ..._recentDebates.map((item) {
                                final color = _outcomeColor(item.outcomeLabel);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.topic,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.status.toUpperCase(),
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.4),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color:
                                                  color.withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              item.outcomeLabel,
                                              style: TextStyle(
                                                color: color,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDate(item.createdAt),
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.3),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _boxingStat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
      IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1A2035),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
