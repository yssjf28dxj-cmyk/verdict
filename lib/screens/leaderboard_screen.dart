import 'package:verdict/firestore_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _leadersFuture;
  final ValueNotifier<bool> _isRefreshing = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _leadersFuture = _fetchLeaders();
  }

  @override
  void dispose() {
    _isRefreshing.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchLeaders() async {
    final snapshot = await appFirestore
        .collection('users')
        .orderBy('wins', descending: true)
        .limit(20)
        .get();
    return snapshot.docs;
  }

  Future<void> _refresh() async {
    _isRefreshing.value = true;
    setState(() {
      _leadersFuture = _fetchLeaders();
    });
    try {
      await _leadersFuture;
    } finally {
      _isRefreshing.value = false;
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  String _username(Map<String, dynamic> data) {
    final name = (data['name'] ?? data['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final publicId = (data['publicId'] ?? '').toString().trim();
    if (publicId.isNotEmpty) return publicId;
    return 'Fighter';
  }

  Color _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return Colors.white54;
  }

  Widget _avatar(Map<String, dynamic> data, String username) {
    final photoUrl =
        (data['photoURL'] ?? data['avatarUrl'] ?? '').toString().trim();
    if (photoUrl.isEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.white.withValues(alpha: 0.09),
        child: Text(
          username.characters.first.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.white.withValues(alpha: 0.09),
      backgroundImage: NetworkImage(photoUrl),
      onBackgroundImageError: (_, __) {},
    );
  }

  Widget _leaderItem({
    required int rank,
    required Map<String, dynamic> data,
  }) {
    final username = _username(data);
    final wins = _asInt(data['wins']);
    final medalColor = _rankColor(rank);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: rank <= 3
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium,
                            size: 18, color: medalColor),
                        const SizedBox(height: 2),
                        Text(
                          '$rank',
                          style: TextStyle(
                            color: medalColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
            _avatar(data, username),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              '$wins wins',
              style: const TextStyle(
                color: VerdictStyle.accentGold,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isRefreshing,
            builder: (context, refreshing, _) {
              if (refreshing) {
                return const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.1,
                        color: VerdictStyle.accentGold,
                      ),
                    ),
                  ),
                );
              }
              return IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _leadersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child:
                      CircularProgressIndicator(color: VerdictStyle.accentGold),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Failed to load leaderboard',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final docs = snapshot.data ?? const [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No users yet',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  0,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                  0,
                  24,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  return _leaderItem(rank: index + 1, data: docs[index].data());
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
