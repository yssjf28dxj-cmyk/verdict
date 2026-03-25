import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'create_debate_screen.dart';
import 'debate_room_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'world_chat_screen.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/name_utils.dart';
import '../utils/rank_utils.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _search = '';
  String _feedLanguage = 'all';
  String _feedRegion = 'global';
  final TextEditingController _searchController = TextEditingController();

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

  bool _canSeeDebateInFeed(Map<String, dynamic> data, String uid) {
    final visibility = (data['visibilityMode'] ?? 'public').toString();
    final creationMode = (data['creationMode'] ?? 'public_feed').toString();
    final fighter1 = (data['fighter1'] ?? '').toString();
    final fighter2 = (data['fighter2'] ?? '').toString();
    final creatorId = (data['creatorId'] ?? '').toString();
    final invitedUserId = (data['invitedUserId'] ?? '').toString();
    final invitedUserIdsRaw = data['invitedUserIds'];
    final invitedUserIds = invitedUserIdsRaw is List
        ? invitedUserIdsRaw.map((e) => e.toString()).toList()
        : <String>[];

    final isParticipant = uid.isNotEmpty &&
        (uid == fighter1 ||
            uid == fighter2 ||
            uid == creatorId ||
            uid == invitedUserId ||
            invitedUserIds.contains(uid));

    if (visibility == 'private') return isParticipant;
    if (creationMode == 'direct_invite' && !isParticipant) return false;
    return true;
  }

  bool _canAccessDebate(Map<String, dynamic> data, String uid) {
    final visibility = (data['visibilityMode'] ?? 'public').toString();
    final creationMode = (data['creationMode'] ?? 'public_feed').toString();
    final fighter1 = (data['fighter1'] ?? '').toString();
    final fighter2 = (data['fighter2'] ?? '').toString();
    final creatorId = (data['creatorId'] ?? '').toString();
    final invitedUserId = (data['invitedUserId'] ?? '').toString();
    final invitedUserIdsRaw = data['invitedUserIds'];
    final invitedUserIds = invitedUserIdsRaw is List
        ? invitedUserIdsRaw.map((e) => e.toString()).toList()
        : <String>[];
    final approvedUserIds = _stringList(data['accessApprovedUserIds']);

    final isParticipant = uid.isNotEmpty &&
        (uid == fighter1 ||
            uid == fighter2 ||
            uid == creatorId ||
            uid == invitedUserId ||
            invitedUserIds.contains(uid));

    if (visibility == 'request_only') {
      if (!uid.isNotEmpty) return false;
      return isParticipant || approvedUserIds.contains(uid);
    }
    if (visibility == 'private') return isParticipant;
    if (creationMode == 'direct_invite' && !isParticipant) return false;
    return true;
  }

  bool _matchesFeedFilters(Map<String, dynamic> data) {
    final region = (data['region'] ?? 'global').toString();
    final language = (data['languageCode'] ?? 'ru').toString();
    final languageOk = _feedLanguage == 'all' || language == _feedLanguage;
    final regionOk = _feedRegion == 'global' || region == _feedRegion;
    return languageOk && regionOk;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onNavTap(int idx) {
    if (idx == 0) {
      setState(() => _selectedIndex = 0);
      return;
    }

    Widget? target;
    if (idx == 1) {
      target = const LeaderboardScreen();
    } else if (idx == 2) {
      target = const WorldChatScreen();
    } else if (idx == 3) {
      target = const ProfileScreen();
    }
    if (target == null) return;

    setState(() => _selectedIndex = idx);
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => target!,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedIndex = 0);
    });
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + kToolbarHeight + 12,
        16,
        8,
      ),
      child: GlassCard(
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _safeLocalizedText(
                  l10n.searchDebates,
                  'Search debates',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0x662A3147),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _feedLanguage,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            _safeLocalizedText(
                                l10n.languageAll, 'Language: all'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'ru',
                          child: Text(
                            l10n.themeLanguageRU,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'en',
                          child: Text(
                            l10n.themeLanguageEN,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'ar',
                          child: Text(
                            l10n.themeLanguageAR,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _feedLanguage = v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _feedRegion,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'global',
                          child: Text(
                            _safeLocalizedText(l10n.regionGlobal, 'Global'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'cis',
                          child: Text(
                            l10n.regionCis,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'mena',
                          child: Text(
                            l10n.regionMena,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'europe_africa',
                          child: Text(
                            l10n.regionEuAf,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _feedRegion = v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebateList(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('debates')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${l10n.errorLoading}: ${snapshot.error}'));
        }
        final docs = snapshot.data?.docs ?? [];
        final filtered = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (!_canSeeDebateInFeed(data, uid)) return false;
          if (!_matchesFeedFilters(data)) return false;
          if (_search.isEmpty) return true;
          final topic = (data['topic'] ?? '').toString().toLowerCase();
          return topic.contains(_search.toLowerCase());
        }).toList();
        if (filtered.isEmpty) {
          return Center(
            child:
                Text(l10n.noDebatesFound, style: const TextStyle(fontSize: 18)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final data = filtered[i].data() as Map<String, dynamic>;
            final canEnter = _canAccessDebate(data, uid);
            return _DebateCard(
              doc: filtered[i],
              currentUid: uid,
              canEnter: canEnter,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        title: Text(_safeLocalizedText(l10n.appTitle, 'VERDICT')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const ProfileScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
                transitionDuration: const Duration(milliseconds: 200),
              ),
            ),
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
          Column(
            children: [
              _buildSearchBar(l10n),
              Expanded(child: _buildDebateList(l10n)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const CreateDebateScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(l10n.createDebates),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: _safeLocalizedText(l10n.mainTab, 'Home'),
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'Top',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.forum_outlined),
            label: _safeLocalizedText(l10n.worldChatTab, 'Chat'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: _safeLocalizedText(l10n.profileTab, 'Profile'),
          ),
        ],
        selectedItemColor: VerdictStyle.accentGold,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        backgroundColor: const Color(0xFF0E1320),
      ),
    );
  }
}

class _DebateCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final String currentUid;
  final bool canEnter;
  const _DebateCard({
    required this.doc,
    required this.currentUid,
    required this.canEnter,
  });

  @override
  State<_DebateCard> createState() => _DebateCardState();
}

class _DebateCardState extends State<_DebateCard> {
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

  bool _isWaitingStatus(String status) {
    return status.toLowerCase() == 'waiting';
  }

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
    await FirebaseFirestore.instance
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
      final callable = _functions.httpsCallable('moderateAccessRequest');
      await callable.call({
        'debateId': debateId,
        'targetUid': targetUid,
        'action': 'approve',
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accessApproved)),
      );
    } on FirebaseFunctionsException catch (e) {
      final fallbackCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };
      if (!fallbackCodes.contains(e.code)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mapCallableError(
              l10n,
              e,
              fallbackMessage: l10n.approveAccessFailed,
            )),
          ),
        );
        return;
      }

      try {
        await _moderateAccessViaFallback(
          debateId: debateId,
          targetUid: targetUid,
          approve: true,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.accessApproved)),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.approveAccessFailed)),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.approveAccessFailed)),
      );
    }
  }

  Future<void> _rejectAccess({
    required BuildContext context,
    required String debateId,
    required String targetUid,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final callable = _functions.httpsCallable('moderateAccessRequest');
      await callable.call({
        'debateId': debateId,
        'targetUid': targetUid,
        'action': 'reject',
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.requestRejected)),
      );
    } on FirebaseFunctionsException catch (e) {
      final fallbackCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };
      if (!fallbackCodes.contains(e.code)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mapCallableError(
              l10n,
              e,
              fallbackMessage: l10n.rejectRequestFailed,
            )),
          ),
        );
        return;
      }

      try {
        await _moderateAccessViaFallback(
          debateId: debateId,
          targetUid: targetUid,
          approve: false,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.requestRejected)),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.rejectRequestFailed)),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.rejectRequestFailed)),
      );
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
              itemBuilder: (ctx, index) {
                final uid = requests[index];
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        uid,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.reject,
                      onPressed: () => _rejectAccess(
                        context: dialogContext,
                        debateId: debateId,
                        targetUid: uid,
                      ),
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                    ),
                    IconButton(
                      tooltip: l10n.approve,
                      onPressed: () => _approveAccess(
                        context: dialogContext,
                        debateId: debateId,
                        targetUid: uid,
                      ),
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
    BuildContext context,
    String debateId,
    bool alreadyRequested,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (currentUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginToRequestAccess)),
      );
      return;
    }

    if (alreadyRequested) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.requestAlreadySent)),
      );
      return;
    }

    try {
      final callable = _functions.httpsCallable('requestDebateAccess');
      await callable.call({
        'debateId': debateId,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accessRequestSent)),
      );
    } on FirebaseFunctionsException catch (e) {
      final fallbackCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };
      if (!fallbackCodes.contains(e.code)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mapCallableError(
              l10n,
              e,
              fallbackMessage: l10n.sendRequestFailed,
            )),
          ),
        );
        return;
      }

      try {
        await FirebaseFirestore.instance
            .collection('debates')
            .doc(debateId)
            .update({
          'accessRequests': FieldValue.arrayUnion([currentUid]),
        });
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.accessRequestSent)),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.sendRequestFailed)),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sendRequestFailed)),
      );
    }
  }

  void _navigateToDebate(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            DebateRoomScreen(debateId: doc.id),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  /// One-click join: calls acceptDebateInvite, then navigates to room
  Future<void> _joinAsFighter(BuildContext context) async {
    if (_isJoining) return;
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
      // If already joined or debate started — just navigate
      if (e.code == 'already-exists' || e.code == 'failed-precondition') {
        _navigateToDebate(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapCallableError(l10n, e,
              fallbackMessage: 'Failed to join debate')),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to join debate')),
      );
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // ─── DARK-THEMED CARD WIDGETS ─────────────────────────────

  Widget _buildStatusBadge(String status) {
    if (_isLiveStatus(status)) {
      return const LivePulseIndicator();
    }

    if (_isWaitingStatus(status)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: VerdictStyle.accentGold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: VerdictStyle.accentGold.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: VerdictStyle.accentGold,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'WAITING',
              style: TextStyle(
                color: VerdictStyle.accentGold,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 0.6,
              ),
            ),
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
      child: const Text(
        'FINISHED',
        style: TextStyle(
          color: Colors.white38,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildFighterAvatar({
    required String name,
    required Color color,
    bool isEmpty = false,
    double rating = 0,
  }) {
    final rank = getRank(rating);

    return Expanded(
      child: Column(
        children: [
          Container(
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
              boxShadow: (!isEmpty &&
                      (rank.key == 'master' || rank.key == 'grandmaster'))
                  ? [
                      BoxShadow(
                          color: rank.glowColor,
                          blurRadius: 10,
                          spreadRadius: 1)
                    ]
                  : null,
            ),
            child: isEmpty
                ? Icon(Icons.person_add_alt_1,
                    color: color.withValues(alpha: 0.4), size: 22)
                : Icon(Icons.person, color: color, size: 24),
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

  Widget _metaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white54,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _votePill({required Color color, required int votes}) {
    return Container(
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
          Text(
            '$votes',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _prettyVisibility(AppLocalizations l10n, String mode) {
    switch (mode) {
      case 'private':
        return l10n.privateMode;
      case 'request_only':
        return l10n.requestOnly;
      default:
        return l10n.publicMode;
    }
  }

  String _prettyRegion(AppLocalizations l10n, String region) {
    switch (region) {
      case 'cis':
        return l10n.regionCis;
      case 'mena':
        return l10n.regionMena;
      case 'europe_africa':
        return l10n.regionEuAf;
      default:
        return l10n.regionGlobal;
    }
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
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
              colors: [
                color,
                color.withValues(alpha: 0.7),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = doc.data() as Map<String, dynamic>;
    final String topic = _safeLocalizedText(
      (data['topic'] ?? '').toString(),
      _safeLocalizedText(l10n.topicNotSpecified, 'Topic not specified'),
    );
    final String fighter1 = firstNonEmptyName(
      [data['fighter1Name'], data['fighter1']],
      fallback: l10n.fighterOne,
    );
    final String fighter2 = firstNonEmptyName(
      [data['fighter2Name'], data['fighter2']],
      fallback: l10n.fighterTwo,
    );
    final String status = (data['status'] ?? 'live').toString();
    final int votes1 =
        (data['votes1'] is num) ? (data['votes1'] as num).toInt() : 0;
    final int votes2 =
        (data['votes2'] is num) ? (data['votes2'] as num).toInt() : 0;
    final int viewers =
        (data['viewerCount'] is num) ? (data['viewerCount'] as num).toInt() : 0;
    final String visibility =
        (data['visibilityMode'] ?? 'public').toString().toLowerCase();
    final String language =
        (data['languageCode'] ?? 'ru').toString().toUpperCase();
    final String region = (data['region'] ?? 'global').toString().toLowerCase();
    final String creatorId = (data['creatorId'] ?? '').toString();
    final accessRequests = _stringList(data['accessRequests']);
    final alreadyRequested = accessRequests.contains(currentUid);
    final isCreator = currentUid.isNotEmpty && currentUid == creatorId;
    final int currentRound = (data['currentRound'] is num)
        ? (data['currentRound'] as num).toInt()
        : 1;
    final int totalRounds =
        (data['totalRounds'] is num) ? (data['totalRounds'] as num).toInt() : 1;
    final double f1Rating = (data['fighter1Rating'] is num)
        ? (data['fighter1Rating'] as num).toDouble()
        : 0;
    final double f2Rating = (data['fighter2Rating'] is num)
        ? (data['fighter2Rating'] as num).toDouble()
        : 0;

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
                  ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.accessRestricted)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: Status badge + meta chips ──
                  Row(
                    children: [
                      _buildStatusBadge(status),
                      const Spacer(),
                      if (isLive) ...[
                        Icon(Icons.visibility,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Text(
                          '$viewers',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      ...[
                        _metaChip(language),
                        const SizedBox(width: 4),
                        _metaChip(_prettyRegion(l10n, region)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Topic ──
                  Text(
                    topic,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Fighters arena ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildFighterAvatar(
                          name: fighter1,
                          color: VerdictStyle.fighterBlue,
                          rating: f1Rating,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              const Text(
                                'VS',
                                style: TextStyle(
                                  color: VerdictStyle.accentGold,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              if (isLive) ...[
                                const SizedBox(height: 4),
                                Text(
                                  l10n.roundProgress(currentRound, totalRounds),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        _buildFighterAvatar(
                          name: isWaiting && !hasFighter2 ? '?' : fighter2,
                          color: VerdictStyle.fighterRed,
                          isEmpty: isWaiting && !hasFighter2,
                          rating: f2Rating,
                        ),
                      ],
                    ),
                  ),

                  // ── Vote pills for live/finished ──
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
                  ],

                  // ── Action button ──
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
                                  color: VerdictStyle.fighterBlue,
                                ),
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

                  // ── Access request controls ──
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
                        requests: accessRequests,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color:
                              VerdictStyle.fighterBlue.withValues(alpha: 0.1),
                          border: Border.all(
                            color:
                                VerdictStyle.fighterBlue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          '${_safeLocalizedText(l10n.accessRequestsCountPrefix, 'Access requests')}: ${accessRequests.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: VerdictStyle.fighterBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
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
