import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'create_debate_screen.dart';
import 'debate_room_screen.dart';
import 'profile_screen.dart';
import 'world_chat_screen.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/name_utils.dart';
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
    setState(() => _selectedIndex = idx);
    // Навигация между экранами с FadeTransition
    if (idx == 1) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const WorldChatScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
    } else if (idx == 2) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ProfileScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
    }
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
          BottomNavigationBarItem(
            icon: const Icon(Icons.public),
            label: _safeLocalizedText(l10n.worldChatTab, 'World Chat'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: _safeLocalizedText(l10n.profileTab, 'Profile'),
          ),
        ],
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

class _DebateCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final String currentUid;
  final bool canEnter;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  _DebateCard({
    required this.doc,
    required this.currentUid,
    required this.canEnter,
  });

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

  Widget _buildStatusBadge(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context)!;
    final normalized = status.toLowerCase();
    final isLive = normalized == 'live' ||
        normalized == 'active' ||
        normalized.startsWith('round');

    if (isLive) {
      return const LivePulseIndicator();
    }

    if (normalized == 'waiting') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          l10n.waitingStatus,
          style: const TextStyle(
            color: Color(0xFFEF6C00),
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        l10n.finishedStatus,
        style: const TextStyle(
          color: Color(0xFF757575),
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildFighter({required String name, required Color color}) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
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

  Widget _metaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF475569),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _votePill({required Color color, required int votes}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.how_to_vote, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$votes',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 12,
            ),
          ),
        ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassCard(
        enableBlur: false,
        borderRadius: BorderRadius.circular(24),
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            if (canEnter) {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      DebateRoomScreen(debateId: doc.id),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) =>
                          FadeTransition(opacity: animation, child: child),
                  transitionDuration: const Duration(milliseconds: 200),
                ),
              );
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        topic,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Color(0xCC000000),
                              blurRadius: 8,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildStatusBadge(context, status),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _metaChip(language),
                    _metaChip(_prettyVisibility(l10n, visibility)),
                    _metaChip(_prettyRegion(l10n, region)),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x442A3147),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      _buildFighter(
                          name: fighter1, color: const Color(0xFF1976D2)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            color: Color(0xFFFFA500),
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      _buildFighter(
                          name: fighter2, color: const Color(0xFFD32F2F)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(
                      Icons.remove_red_eye_outlined,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                    Text(
                      '$viewers',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                    _votePill(color: const Color(0xFF42A5F5), votes: votes1),
                    _votePill(color: const Color(0xFFEF5350), votes: votes2),
                    if (!canEnter && visibility == 'request_only')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          alreadyRequested
                              ? _safeLocalizedText(
                                  l10n.requestSent, 'Request sent')
                              : _safeLocalizedText(
                                  l10n.requestAccess, 'Request access'),
                          style: const TextStyle(
                            color: Color(0xFFEF6C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    if (isCreator && accessRequests.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _showAccessRequestsDialog(
                          context: context,
                          debateId: doc.id,
                          requests: accessRequests,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0FE),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_safeLocalizedText(l10n.accessRequestsCountPrefix, 'Access requests')}: ${accessRequests.length}',
                            style: const TextStyle(
                              color: Color(0xFF1D4ED8),
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
