import 'package:flutter/material.dart';

/// VERDICT Fighter Rank System
/// Ranks are derived client-side from the `rating` field in Firestore.
class FighterRank {
  final String key;
  final String titleEn;
  final String titleRu;
  final IconData icon;
  final Color color;
  final Color glowColor;
  final int minRating;
  final int maxRating; // -1 = infinity

  const FighterRank._({
    required this.key,
    required this.titleEn,
    required this.titleRu,
    required this.icon,
    required this.color,
    required this.glowColor,
    required this.minRating,
    required this.maxRating,
  });

  /// Progress to the next rank (0.0 – 1.0). Returns 1.0 for max rank.
  double progress(double rating) {
    if (maxRating < 0) return 1.0;
    final range = maxRating - minRating;
    if (range <= 0) return 1.0;
    return ((rating - minRating) / range).clamp(0.0, 1.0);
  }

  /// Points needed to reach the next rank. Returns 0 for max rank.
  int pointsToNext(double rating) {
    if (maxRating < 0) return 0;
    return (maxRating - rating).ceil().clamp(0, 99999);
  }

  String localizedTitle(String langCode) {
    return langCode == 'ru' ? titleRu : titleEn;
  }
}

// ── Rank Definitions ─────────────────────────────────────────

const _ranks = <FighterRank>[
  FighterRank._(
    key: 'rookie',
    titleEn: 'ROOKIE',
    titleRu: 'НОВИЧОК',
    icon: Icons.fiber_new_rounded,
    color: Color(0xFF90A4AE),
    glowColor: Color(0x4490A4AE),
    minRating: 0,
    maxRating: 300,
  ),
  FighterRank._(
    key: 'fighter',
    titleEn: 'FIGHTER',
    titleRu: 'БОЕЦ',
    icon: Icons.sports_mma,
    color: Color(0xFF66BB6A),
    glowColor: Color(0x4466BB6A),
    minRating: 300,
    maxRating: 600,
  ),
  FighterRank._(
    key: 'veteran',
    titleEn: 'VETERAN',
    titleRu: 'ВЕТЕРАН',
    icon: Icons.military_tech,
    color: Color(0xFF42A5F5),
    glowColor: Color(0x4442A5F5),
    minRating: 600,
    maxRating: 1000,
  ),
  FighterRank._(
    key: 'master',
    titleEn: 'MASTER',
    titleRu: 'МАСТЕР',
    icon: Icons.diamond_outlined,
    color: Color(0xFFAB47BC),
    glowColor: Color(0x66AB47BC),
    minRating: 1000,
    maxRating: 1500,
  ),
  FighterRank._(
    key: 'grandmaster',
    titleEn: 'GRANDMASTER',
    titleRu: 'ГРАНДМАСТЕР',
    icon: Icons.auto_awesome,
    color: Color(0xFFFFD700),
    glowColor: Color(0x88FFD700),
    minRating: 1500,
    maxRating: -1,
  ),
];

FighterRank getRank(double rating) {
  for (int i = _ranks.length - 1; i >= 0; i--) {
    if (rating >= _ranks[i].minRating) return _ranks[i];
  }
  return _ranks.first;
}

List<FighterRank> get allRanks => _ranks;

/// Small rank badge widget for use in cards and lists
class RankBadge extends StatelessWidget {
  final double rating;
  final bool showLabel;
  final double iconSize;
  final double fontSize;

  const RankBadge({
    super.key,
    required this.rating,
    this.showLabel = true,
    this.iconSize = 14,
    this.fontSize = 9,
  });

  @override
  Widget build(BuildContext context) {
    final rank = getRank(rating);
    final isElite = rank.key == 'master' || rank.key == 'grandmaster';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: rank.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: rank.color.withValues(alpha: 0.4),
        ),
        boxShadow: isElite
            ? [
                BoxShadow(
                  color: rank.glowColor,
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(rank.icon, size: iconSize, color: rank.color),
          if (showLabel) ...[
            const SizedBox(width: 3),
            Text(
              rank.localizedTitle(
                Localizations.localeOf(context).languageCode,
              ),
              style: TextStyle(
                color: rank.color,
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
