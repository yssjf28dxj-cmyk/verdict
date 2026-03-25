import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/debate_history_item.dart';
import '../utils/rank_utils.dart';
import 'auth_screen.dart';
import 'lobby_screen.dart';
import 'public_profile_screen.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/style_utils.dart';
import 'profile_history_screen.dart';
import 'settings_screen.dart';

class _PublicUserPreview {
  const _PublicUserPreview({
    required this.uid,
    required this.publicId,
    required this.name,
    required this.rating,
    required this.reputation,
    required this.style,
  });

  final String uid;
  final String publicId;
  final String name;
  final double rating;
  final double reputation;
  final String style;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _displayName;
  String _publicId = '';
  int _wins = 0;
  int _losses = 0;
  int _draws = 0;
  double _rating = 0.0;
  double _reputation = 0.0;
  double _viewerScore = 0.0;
  String _debateStyle = 'Balanced';
  int _totalDebates = 0;
  List<DebateHistoryItem> _recentDebates = const [];
  List<DebateHistoryItem> _allDebates = const [];
  bool _isLoading = true;
  bool _isInviting = false;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

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

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  double get _winRate {
    if (_totalDebates <= 0) return 0;
    return ((_wins + (_draws * 0.5)) / _totalDebates) * 100;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    final displayName = user.displayName?.trim();
    _displayName =
        displayName != null && displayName.isNotEmpty ? displayName : null;
    final uid = user.uid;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      Map<String, dynamic>? data = doc.data();
      if (!doc.exists) {
        final generatedId = _generatePublicId(uid);
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'publicId': generatedId,
          'wins': 0,
          'losses': 0,
          'draws': 0,
          'rating': 0,
          'reputation': 0,
          'viewerScore': 0,
          'debateStyle': 'Balanced',
          'totalDebates': 0,
        }, SetOptions(merge: true));
        data = {
          'publicId': generatedId,
          'wins': 0,
          'losses': 0,
          'draws': 0,
          'rating': 0,
          'reputation': 0,
          'viewerScore': 0,
          'debateStyle': 'Balanced',
          'totalDebates': 0,
        };
      }

      if (data != null) {
        var publicId = (data['publicId'] ?? '').toString().trim();
        if (publicId.isEmpty) {
          publicId = _generatePublicId(uid);
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'publicId': publicId,
          }, SetOptions(merge: true));
        }
        setState(() {
          _publicId = publicId;
          _wins = _asInt(data?['wins']);
          _losses = _asInt(data?['losses']);
          _draws = _asInt(data?['draws']);
          _rating = _asDouble(data?['rating']);
          _reputation = _asDouble(data?['reputation']);
          _viewerScore = _asDouble(data?['viewerScore']);
          _debateStyle = (data?['debateStyle'] ?? 'Balanced').toString();
          _totalDebates = _asInt(data?['totalDebates']);
        });
      }

      final debateSnapshots = await Future.wait([
        FirebaseFirestore.instance
            .collection('debates')
            .where('fighter1', isEqualTo: uid)
            .limit(20)
            .get(),
        FirebaseFirestore.instance
            .collection('debates')
            .where('fighter2', isEqualTo: uid)
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
        final isFighter1 = fighter1 == uid;
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

      if (mounted) {
        setState(() {
          _allDebates = history;
          _recentDebates = history.take(5).toList(growable: false);
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _generatePublicId(String uid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return 'VERDICT-USER';
    final tail = trimmed.length > 10 ? trimmed.substring(0, 10) : trimmed;
    return 'VERDICT-${tail.toUpperCase()}';
  }

  Future<void> _copyPublicId() async {
    final l10n = AppLocalizations.of(context)!;
    final id = _publicId.trim();
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.profileIdCopied)),
    );
  }

  void _openFullHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileHistoryScreen(items: _allDebates),
      ),
    );
  }

  String _effectiveDebateLanguageCode() {
    final localeCode = Localizations.localeOf(context).languageCode;
    if (localeCode == 'ru' || localeCode == 'en' || localeCode == 'ar') {
      return localeCode;
    }
    return 'ru';
  }

  Future<void> _createDirectInviteToUid({
    required AppLocalizations l10n,
    required String invitedUid,
    required String topic,
  }) async {
    final callable = _functions.httpsCallable(
      'createDebate',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final payload = {
      'topic': topic,
      'durationSeconds': 180,
      'totalRounds': 3,
      'creationMode': 'direct_invite',
      'visibilityMode': 'private',
      'languageCode': _effectiveDebateLanguageCode(),
      'region': 'global',
      'invitedUserId': invitedUid,
    };

    HttpsCallableResult<dynamic> result;
    try {
      result = await callable.call(payload);
    } on FirebaseFunctionsException catch (e) {
      const retryableCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };
      if (!retryableCodes.contains(e.code)) {
        rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 900));
      result = await callable.call(payload);
    }

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
  }

  Future<void> _createDirectInviteByPublicId({
    required AppLocalizations l10n,
    required String rawPublicId,
    required String rawTopic,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authRequired)),
      );
      return;
    }

    final publicId = rawPublicId.trim().toUpperCase();
    final topic = rawTopic.trim();
    if (publicId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterOpponentId)),
      );
      return;
    }
    if (topic.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterTopic)),
      );
      return;
    }

    setState(() {
      _isInviting = true;
    });

    try {
      final targetSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('publicId', isEqualTo: publicId)
          .limit(1)
          .get();

      if (targetSnap.docs.isEmpty) {
        throw Exception(l10n.userWithIdNotFound);
      }

      final invitedUid = targetSnap.docs.first.id;
      if (invitedUid == currentUser.uid) {
        throw Exception(l10n.cannotAcceptOwnChallenge);
      }
      await _createDirectInviteToUid(
        l10n: l10n,
        invitedUid: invitedUid,
        topic: topic,
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
      if (mounted) {
        setState(() {
          _isInviting = false;
        });
      }
    }
  }

  Future<void> _showInviteByIdDialog(AppLocalizations l10n) async {
    final idController = TextEditingController();
    final topicController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.directInvite),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l10n.opponentId,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: topicController,
                decoration: InputDecoration(
                  labelText: l10n.debateTopicLabel,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.close),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'publicId': idController.text,
                  'topic': topicController.text,
                });
              },
              child: Text(l10n.publishChallenge),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    await _createDirectInviteByPublicId(
      l10n: l10n,
      rawPublicId: result['publicId'] ?? '',
      rawTopic: result['topic'] ?? '',
    );
  }

  Future<String?> _askInviteTopic(
      AppLocalizations l10n, String targetLabel) async {
    final topicController = TextEditingController();
    final topic = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${l10n.directInvite}: $targetLabel'),
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
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.close),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(topicController.text.trim()),
              child: Text(l10n.publishChallenge),
            ),
          ],
        );
      },
    );
    return topic;
  }

  Future<void> _openUserSearchAndInvite(AppLocalizations l10n) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final searchController = TextEditingController();

    final selected = await showModalBottomSheet<_PublicUserPreview>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VerdictStyle.bg,
      builder: (context) {
        String query = '';

        Query<Map<String, dynamic>> buildQuery() {
          final normalized = query.trim().toUpperCase();
          if (normalized.isEmpty) {
            return FirebaseFirestore.instance
                .collection('users')
                .orderBy('publicId')
                .limit(12);
          }
          return FirebaseFirestore.instance
              .collection('users')
              .orderBy('publicId')
              .startAt([normalized]).endAt(['$normalized\uf8ff']).limit(20);
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (value) {
                        setModalState(() {
                          query = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: l10n.searchByPublicIdHint,
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: buildQuery().snapshots(),
                        builder: (context, snapshot) {
                          final docs = snapshot.data?.docs
                                  .where((d) => d.id != currentUid)
                                  .toList() ??
                              const <QueryDocumentSnapshot<
                                  Map<String, dynamic>>>[];

                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (docs.isEmpty) {
                            return Center(
                              child: Text(
                                l10n.noUsersFound,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final data = docs[index].data();
                              final publicId =
                                  (data['publicId'] ?? '').toString().trim();
                              if (publicId.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final name =
                                  (data['name'] ?? data['displayName'] ?? '')
                                      .toString()
                                      .trim();
                              final rating =
                                  (data['rating'] as num?)?.toDouble() ?? 0;
                              final reputation =
                                  (data['reputation'] as num?)?.toDouble() ?? 0;
                              final style = (data['debateStyle'] ?? 'Balanced')
                                  .toString();

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: getRank(rating).color.withValues(alpha: 0.2),
                                  child: Icon(getRank(rating).icon, color: getRank(rating).color),
                                ),
                                title: Text(
                                  name.isNotEmpty ? name : publicId,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Row(
                                  children: [
                                    RankBadge(rating: rating, iconSize: 12, fontSize: 8),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '$publicId  |  ${reputation.toStringAsFixed(0)} rep',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white54, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14),
                                onTap: () {
                                  Navigator.of(context).pop(
                                    _PublicUserPreview(
                                      uid: docs[index].id,
                                      publicId: publicId,
                                      name: name,
                                      rating: rating,
                                      reputation: reputation,
                                      style: style,
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;
    await _showUserActionDialog(l10n, selected);
  }

  Future<void> _showUserActionDialog(
    AppLocalizations l10n,
    _PublicUserPreview selected,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
              selected.name.isNotEmpty ? selected.name : selected.publicId),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(selected.publicId),
              const SizedBox(height: 8),
              RankBadge(rating: selected.rating),
              const SizedBox(height: 8),
              Text('${l10n.rating}: ${selected.rating.toStringAsFixed(1)}'),
              Text(
                  '${l10n.reputation}: ${selected.reputation.toStringAsFixed(1)}'),
              Text('${l10n.styleLabel}: ${selected.style}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('view'),
              child: Text(l10n.viewProfile),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('invite'),
              child: Text(l10n.directInvite),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'view') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PublicProfileScreen(
            uid: selected.uid,
            publicId: selected.publicId,
            name: selected.name,
          ),
        ),
      );
      return;
    }

    final targetLabel = selected.name.isNotEmpty
        ? '${selected.name} (${selected.publicId})'
        : selected.publicId;
    final topic = await _askInviteTopic(l10n, targetLabel);
    if (topic == null || topic.trim().length < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterTopic)),
      );
      return;
    }

    setState(() {
      _isInviting = true;
    });
    try {
      await _createDirectInviteToUid(
        l10n: l10n,
        invitedUid: selected.uid,
        topic: topic.trim(),
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
      if (mounted) {
        setState(() {
          _isInviting = false;
        });
      }
    }
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) return '--';
    final local = createdAt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$day.$month.$year';
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

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuthScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
      (route) => false,
    );
  }

  // ─── BUILD ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rank = getRank(_rating);
    final langCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          l10n.profileTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: VerdictStyle.accentGold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings_outlined),
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
          _isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: VerdictStyle.accentGold),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                    16,
                    100,
                  ),
                  child: Column(
                    children: [
                      // ── HERO FIGHTER CARD ──────────────────
                      _buildHeroCard(l10n, rank, langCode),
                      const SizedBox(height: 16),

                      // ── BOXING STATS W/L/D ─────────────────
                      _buildBoxingStats(l10n),
                      const SizedBox(height: 12),

                      // ── RATING & RANK PROGRESS ─────────────
                      _buildRatingCard(l10n, rank, langCode),
                      const SizedBox(height: 12),

                      // ── DETAILED STATS ─────────────────────
                      _buildDetailedStats(l10n),
                      const SizedBox(height: 12),

                      // ── ACTION BUTTONS ─────────────────────
                      _buildActionButtons(l10n),
                      const SizedBox(height: 16),

                      // ── RECENT DEBATES ─────────────────────
                      _buildRecentDebates(l10n),
                      const SizedBox(height: 16),

                      // ── SIGN OUT ───────────────────────────
                      _buildSignOut(l10n),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  // ── HERO CARD ─────────────────────────────────────────────

  Widget _buildHeroCard(AppLocalizations l10n, FighterRank rank, String langCode) {
    final isElite = rank.key == 'master' || rank.key == 'grandmaster';

    return Container(
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
          // Avatar with rank ring
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
              size: 52,
              color: rank.color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),

          // Fighter name
          Text(
            (_displayName ?? l10n.guest).toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),

          // Rank badge
          RankBadge(rating: _rating, iconSize: 16, fontSize: 11),
          const SizedBox(height: 10),

          // Public ID
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _publicId.isNotEmpty ? _publicId : 'VERDICT-USER',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: _copyPublicId,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Debate style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  '${l10n.styleLabel}: ${_debateStyle.isNotEmpty ? _debateStyle : l10n.balancedStyle}',
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
    );
  }

  // ── BOXING W/L/D STATS ────────────────────────────────────

  Widget _buildBoxingStats(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1A2035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          // W — L — D header
          Row(
            children: [
              Expanded(
                child: _boxingStat(
                  value: '$_wins',
                  label: l10n.wins,
                  color: const Color(0xFF4CAF50),
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              Expanded(
                child: _boxingStat(
                  value: '$_losses',
                  label: l10n.losses,
                  color: const Color(0xFFFF6B6B),
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              Expanded(
                child: _boxingStat(
                  value: '$_draws',
                  label: l10n.draws,
                  color: const Color(0xFFFFB74D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Win Rate bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.winRate,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
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
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
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
        ],
      ),
    );
  }

  Widget _boxingStat({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
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
    );
  }

  // ── RATING & RANK PROGRESS ────────────────────────────────

  Widget _buildRatingCard(AppLocalizations l10n, FighterRank rank, String langCode) {
    final progress = rank.progress(_rating);
    final toNext = rank.pointsToNext(_rating);
    final isMaxRank = rank.maxRating < 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1A2035),
        border: Border.all(
          color: rank.color.withValues(alpha: 0.2),
        ),
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
                  letterSpacing: 0.6,
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

          // Progress bar to next rank
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(rank.color),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rank.localizedTitle(langCode),
                    style: TextStyle(
                      color: rank.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    isMaxRank ? 'MAX RANK' : '$toNext pts to next',
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
        ],
      ),
    );
  }

  // ── DETAILED STATS ────────────────────────────────────────

  Widget _buildDetailedStats(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _miniStat(
            icon: Icons.bolt,
            label: l10n.battles,
            value: '$_totalDebates',
            color: VerdictStyle.fighterRed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            icon: Icons.shield,
            label: l10n.reputation,
            value: _reputation.toStringAsFixed(0),
            color: const Color(0xFF4DB6AC),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            icon: Icons.groups_rounded,
            label: l10n.audience,
            value: _viewerScore.toStringAsFixed(0),
            color: const Color(0xFF64B5F6),
          ),
        ),
      ],
    );
  }

  Widget _miniStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
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
    );
  }

  // ── ACTION BUTTONS ────────────────────────────────────────

  Widget _buildActionButtons(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            icon: _isInviting
                ? null
                : Icons.person_search,
            label: _isInviting ? '...' : l10n.directInvite,
            color: VerdictStyle.fighterBlue,
            onTap: _isInviting ? null : () => _showInviteByIdDialog(l10n),
            isLoading: _isInviting,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            icon: Icons.travel_explore_rounded,
            label: l10n.findFighterById,
            color: VerdictStyle.accentGold,
            onTap: _isInviting ? null : () => _openUserSearchAndInvite(l10n),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData? icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else if (icon != null)
                Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── RECENT DEBATES ────────────────────────────────────────

  Widget _buildRecentDebates(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1A2035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: Colors.white38, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.recentDebates,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (_allDebates.isNotEmpty)
                InkWell(
                  onTap: _openFullHistory,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      l10n.viewAll,
                      style: TextStyle(
                        color: VerdictStyle.accentGold.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentDebates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  l10n.noDebatesYet,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            ..._recentDebates.map((item) => _debateHistoryTile(item, l10n)),
        ],
      ),
    );
  }

  Widget _debateHistoryTile(DebateHistoryItem item, AppLocalizations l10n) {
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
          // Outcome indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 3),
                Text(
                  '${l10n.versusLabel} ${item.opponentLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Outcome + date
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.outcomeLabel,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatCreatedAt(item.createdAt),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── SIGN OUT ──────────────────────────────────────────────

  Widget _buildSignOut(AppLocalizations l10n) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _signOut,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFF4B4B).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, size: 18, color: const Color(0xFFFF7D7D).withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                l10n.signOut,
                style: TextStyle(
                  color: const Color(0xFFFF7D7D).withValues(alpha: 0.7),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
