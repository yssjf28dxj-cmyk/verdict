import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/debate_history_item.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';

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
  int _wins = 0;
  int _losses = 0;
  int _draws = 0;
  int _totalDebates = 0;
  double _rating = 0;
  double _reputation = 0;
  double _viewerScore = 0;
  String _style = 'Balanced';
  List<DebateHistoryItem> _recentDebates = const [];

  @override
  void initState() {
    super.initState();
    _load();
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

      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
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

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: VerdictStyle.bg,
        foregroundColor: Colors.white,
        title: const Text('Fighter Profile'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        GlassCard(
                          child: Column(
                            children: [
                              const Icon(Icons.person,
                                  size: 54, color: Colors.white),
                              const SizedBox(height: 8),
                              Text(
                                widget.name.isNotEmpty
                                    ? widget.name
                                    : widget.publicId,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.publicId,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Style: $_style  |  Audience: ${_viewerScore.toStringAsFixed(1)}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _stat('WINS', '$_wins', Icons.emoji_events,
                                VerdictStyle.accentGold),
                            const SizedBox(width: 8),
                            _stat('LOSSES', '$_losses', Icons.trending_down,
                                const Color(0xFFFF6B6B)),
                            const SizedBox(width: 8),
                            _stat('DRAWS', '$_draws', Icons.handshake,
                                const Color(0xFFFFB74D)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stat('RATING', _rating.toStringAsFixed(1),
                                Icons.star, VerdictStyle.fighterBlue),
                            const SizedBox(width: 8),
                            _stat('REPUTATION', _reputation.toStringAsFixed(1),
                                Icons.shield, const Color(0xFF4DB6AC)),
                            const SizedBox(width: 8),
                            _stat('BATTLES', '$_totalDebates', Icons.bolt,
                                VerdictStyle.fighterRed),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'RECENT DEBATES',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_recentDebates.isEmpty)
                                const Text(
                                  'No recent debates',
                                  style: TextStyle(color: Colors.white70),
                                )
                              else
                                ..._recentDebates.map((item) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.12),
                                      ),
                                    ),
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
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              item.outcomeLabel,
                                              style: TextStyle(
                                                color: _outcomeColor(
                                                    item.outcomeLabel),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              item.status.toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 11,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _formatDate(item.createdAt),
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11,
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
                ),
        ],
      ),
    );
  }
}
