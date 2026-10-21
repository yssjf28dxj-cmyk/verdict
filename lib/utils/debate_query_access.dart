import 'package:cloud_firestore/cloud_firestore.dart';

/// Restrict queries before downloading documents; UI filtering is not security.
/// Request-only cards are discoverable, but their messages require approval.
Filter debateCardAccessFilter(String uid) {
  final visibleCards = Filter(
    'visibilityMode',
    whereIn: ['public', 'request_only'],
  );
  if (uid.isEmpty) return visibleCards;

  return Filter.or(
    visibleCards,
    Filter('fighter1', isEqualTo: uid),
    Filter('fighter2', isEqualTo: uid),
    Filter('creatorId', isEqualTo: uid),
    Filter('invitedUserId', isEqualTo: uid),
    Filter('invitedUserIds', arrayContains: uid),
  );
}
