import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/rank_utils.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import 'public_profile_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  String _regionFilter = 'all';
  late final AnimationController _podiumAnim;

  @override
  void initState() {
    super.initState();
    _podiumAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _podiumAnim.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _buildQuery() {
    var query = FirebaseFirestore.instance
        .collection('users')
        .orderBy('rating', descending: true)
        .limit(50);

    if (_regionFilter != 'all') {
      query = FirebaseFirestore.instance
          .collection('users')
          .where('region', isEqualTo: _regionFilter)
          .orderBy('rating', descending: true)
          .limit(50);
    }

    return query;
  }

  void _openProfile(String uid, String name, String publicId) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid == currentUid) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PublicProfileScreen(uid: uid, publicId: publicId, name: name),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'LEADERBOARD',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: VerdictStyle.accentGold,
            fontSize: 16,
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight + 8),

              // ── Region filter chips ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('all', 'GLOBAL', l10n),
                      _filterChip('cis', l10n.regionCis, l10n),
                      _filterChip('mena', l10n.regionMena, l10n),
                      _filterChip('europe_africa', l10n.regionEuAf, l10n),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Leaderboard list ──
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _buildQuery().snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: VerdictStyle.accentGold),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '${l10n.errorLoading}: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          l10n.noUsersFound,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 16),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final uid = docs[index].id;
                        final name = _extractName(data);
                        final publicId =
                            (data['publicId'] ?? '').toString().trim();
                        final rating =
                            (data['rating'] as num?)?.toDouble() ?? 0;
                        final wins = (data['wins'] as int?) ?? 0;
                        final losses = (data['losses'] as int?) ?? 0;
                        final totalDebates =
                            (data['totalDebates'] as int?) ?? 0;
                        final isMe = uid == currentUid;

                        // Top 3 = podium
                        if (index < 3) {
                          return _buildPodiumCard(
                            position: index + 1,
                            uid: uid,
                            name: name,
                            publicId: publicId,
                            rating: rating,
                            wins: wins,
                            losses: losses,
                            totalDebates: totalDebates,
                            isMe: isMe,
                          );
                        }

                        return _buildListTile(
                          position: index + 1,
                          uid: uid,
                          name: name,
                          publicId: publicId,
                          rating: rating,
                          wins: wins,
                          losses: losses,
                          totalDebates: totalDebates,
                          isMe: isMe,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _extractName(Map<String, dynamic> data) {
    final name = (data['name'] ?? data['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty && name.length < 20) return name;
    final publicId = (data['publicId'] ?? '').toString().trim();
    if (publicId.isNotEmpty) return publicId;
    return 'Fighter';
  }

  Widget _filterChip(String value, String label, AppLocalizations l10n) {
    final isSelected = _regionFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _regionFilter = value),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: isSelected
                  ? VerdictStyle.accentGold.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: isSelected
                    ? VerdictStyle.accentGold.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? VerdictStyle.accentGold : Colors.white54,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── PODIUM CARD (Top 3) ──────────────────────────────────

  Widget _buildPodiumCard({
    required int position,
    required String uid,
    required String name,
    required String publicId,
    required double rating,
    required int wins,
    required int losses,
    required int totalDebates,
    required bool isMe,
  }) {
    final rank = getRank(rating);
    final isElite = rank.key == 'master' || rank.key == 'grandmaster';

    final Color medalColor;
    final IconData medalIcon;
    final double cardScale;
    switch (position) {
      case 1:
        medalColor = const Color(0xFFFFD700);
        medalIcon = Icons.emoji_events;
        cardScale = 1.0;
        break;
      case 2:
        medalColor = const Color(0xFFC0C0C0);
        medalIcon = Icons.emoji_events;
        cardScale = 0.95;
        break;
      default:
        medalColor = const Color(0xFFCD7F32);
        medalIcon = Icons.emoji_events;
        cardScale = 0.92;
    }

    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, 0.3 + position * 0.1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _podiumAnim,
        curve: Interval(
          position * 0.1,
          0.5 + position * 0.15,
          curve: Curves.easeOutCubic,
        ),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _podiumAnim,
          curve: Interval(
            position * 0.1,
            0.5 + position * 0.15,
            curve: Curves.easeOut,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openProfile(uid, name, publicId),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      medalColor.withValues(alpha: 0.12),
                      const Color(0xFF1A2035),
                      medalColor.withValues(alpha: 0.04),
                    ],
                  ),
                  border: Border.all(
                    color: medalColor.withValues(alpha: 0.35),
                    width: position == 1 ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: medalColor.withValues(alpha: position == 1 ? 0.2 : 0.1),
                      blurRadius: position == 1 ? 25 : 15,
                      spreadRadius: position == 1 ? 2 : 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Medal + position
                    SizedBox(
                      width: 50,
                      child: Column(
                        children: [
                          Icon(medalIcon, color: medalColor, size: 28 * cardScale),
                          const SizedBox(height: 2),
                          Text(
                            '#$position',
                            style: TextStyle(
                              color: medalColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 14 * cardScale,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Avatar
                    Container(
                      width: 48 * cardScale,
                      height: 48 * cardScale,
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
                          width: 2,
                        ),
                        boxShadow: isElite
                            ? [BoxShadow(color: rank.glowColor, blurRadius: 12)]
                            : null,
                      ),
                      child: Icon(
                        Icons.person,
                        size: 24 * cardScale,
                        color: rank.color.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Name + rank + stats
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isMe
                                        ? VerdictStyle.accentGold
                                        : Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: VerdictStyle.accentGold
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'YOU',
                                    style: TextStyle(
                                      color: VerdictStyle.accentGold,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              RankBadge(
                                  rating: rating, iconSize: 12, fontSize: 8),
                              const SizedBox(width: 8),
                              Text(
                                '$wins W · $losses L · $totalDebates fights',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Rating
                    Column(
                      children: [
                        Text(
                          rating.toStringAsFixed(0),
                          style: TextStyle(
                            color: medalColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 22 * cardScale,
                          ),
                        ),
                        Text(
                          'ELO',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── LIST TILE (position 4+) ──────────────────────────────

  Widget _buildListTile({
    required int position,
    required String uid,
    required String name,
    required String publicId,
    required double rating,
    required int wins,
    required int losses,
    required int totalDebates,
    required bool isMe,
  }) {
    final rank = getRank(rating);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openProfile(uid, name, publicId),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isMe
                  ? VerdictStyle.accentGold.withValues(alpha: 0.06)
                  : const Color(0xFF1A2035),
              border: Border.all(
                color: isMe
                    ? VerdictStyle.accentGold.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.04),
              ),
            ),
            child: Row(
              children: [
                // Position
                SizedBox(
                  width: 32,
                  child: Text(
                    '#$position',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),

                // Avatar
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rank.color.withValues(alpha: 0.12),
                    border: Border.all(
                      color: rank.color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    Icons.person,
                    size: 18,
                    color: rank.color.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + rank
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isMe
                                    ? VerdictStyle.accentGold
                                    : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: VerdictStyle.accentGold
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  color: VerdictStyle.accentGold,
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          RankBadge(
                              rating: rating,
                              showLabel: false,
                              iconSize: 11),
                          const SizedBox(width: 6),
                          Text(
                            '$wins W · $losses L',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Rating
                Text(
                  rating.toStringAsFixed(0),
                  style: TextStyle(
                    color: rank.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
