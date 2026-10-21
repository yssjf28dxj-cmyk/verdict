import 'package:verdict/firestore_database.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';
import '../utils/debate_query_access.dart';
import '../widgets/debate_card.dart';

class HomeDebateList extends StatelessWidget {
  final String searchQuery;
  final String feedLanguage;
  final String feedRegion;

  const HomeDebateList({
    super.key,
    required this.searchQuery,
    required this.feedLanguage,
    required this.feedRegion,
  });

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
    final languageOk = feedLanguage == 'all' || language == feedLanguage;
    final regionOk = feedRegion == 'global' || region == feedRegion;
    return languageOk && regionOk;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: appFirestore
          .collection('debates')
          .where(debateCardAccessFilter(uid))
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
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
          if (searchQuery.isEmpty) return true;
          final topic = (data['topic'] ?? '').toString().toLowerCase();
          return topic.contains(searchQuery.toLowerCase());
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
            return DebateCard(
              key: ValueKey(filtered[i].id),
              doc: filtered[i],
              currentUid: uid,
              canEnter: canEnter,
            );
          },
        );
      },
    );
  }
}
