import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/debate_history_item.dart';
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
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0x332196F3),
                                  child:
                                      Icon(Icons.person, color: Colors.white),
                                ),
                                title: Text(
                                  name.isNotEmpty ? name : publicId,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  '$publicId   |   ${l10n.rating}: ${rating.toStringAsFixed(1)}   |   ${l10n.reputation}: ${reputation.toStringAsFixed(1)}   |   $style',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
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
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(
                                  height: MediaQuery.of(context).padding.top),
                              GlassCard(
                                child: Column(
                                  children: [
                                    Container(
                                      width: 110,
                                      height: 110,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: VerdictStyle.accentGold
                                              .withValues(alpha: 0.7),
                                        ),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0x332196F3),
                                            Color(0x33FF4B4B),
                                          ],
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.person,
                                        size: 62,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      (_displayName ?? l10n.guest)
                                          .toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _publicId.isNotEmpty
                                                ? _publicId
                                                : 'VERDICT-USER',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: l10n.copyIdTooltip,
                                          onPressed: _copyPublicId,
                                          icon: const Icon(
                                            Icons.copy_rounded,
                                            size: 18,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _isInviting
                                            ? null
                                            : () => _showInviteByIdDialog(l10n),
                                        icon: _isInviting
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.black,
                                                ),
                                              )
                                            : const Icon(Icons.person_search),
                                        label: Text(
                                          _isInviting
                                              ? '...'
                                              : l10n.directInvite,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isInviting
                                            ? null
                                            : () =>
                                                _openUserSearchAndInvite(l10n),
                                        icon: const Icon(
                                            Icons.travel_explore_rounded),
                                        label: Text(l10n.findFighterById),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.wins,
                                      '$_wins',
                                      Icons.emoji_events,
                                      VerdictStyle.accentGold,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.rating,
                                      _rating.toStringAsFixed(1),
                                      Icons.star,
                                      VerdictStyle.fighterBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.battles,
                                      '$_totalDebates',
                                      Icons.bolt,
                                      VerdictStyle.fighterRed,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.losses,
                                      '$_losses',
                                      Icons.trending_down,
                                      const Color(0xFFFF6B6B),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.draws,
                                      '$_draws',
                                      Icons.handshake,
                                      const Color(0xFFFFB74D),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.reputation,
                                      _reputation.toStringAsFixed(1),
                                      Icons.shield,
                                      const Color(0xFF4DB6AC),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.winRate,
                                      '${_winRate.toStringAsFixed(1)}%',
                                      Icons.percent,
                                      const Color(0xFF81C784),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildStatCard(
                                      l10n.audience,
                                      _viewerScore.toStringAsFixed(1),
                                      Icons.groups_rounded,
                                      const Color(0xFF64B5F6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              GlassCard(
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.psychology_alt_outlined,
                                      color: VerdictStyle.accentGold,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${l10n.styleLabel}: ${_debateStyle.isNotEmpty ? _debateStyle : l10n.balancedStyle}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              GlassCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            l10n.recentDebates,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ),
                                        if (_allDebates.isNotEmpty)
                                          TextButton(
                                            onPressed: _openFullHistory,
                                            child: Text(l10n.viewAll),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (_recentDebates.isEmpty)
                                      Text(
                                        l10n.noDebatesYet,
                                        style: const TextStyle(
                                            color: Colors.white70),
                                      )
                                    else
                                      ..._recentDebates.map((item) {
                                        return Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.16),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.14),
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
                                              Text(
                                                '${l10n.versusLabel} ${item.opponentLabel}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
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
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    item.status.toUpperCase(),
                                                    style: const TextStyle(
                                                      color: Colors.white60,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    _formatCreatedAt(
                                                        item.createdAt),
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
                      const SizedBox(height: 12),
                      GlassCard(
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout),
                            label: Text(l10n.signOut),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF7D7D),
                              side: const BorderSide(color: Color(0xFFFF4B4B)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
