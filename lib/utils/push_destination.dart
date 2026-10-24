import 'package:go_router/go_router.dart';
import 'invitation_links.dart';

class PushDestination {
  const PushDestination._(
      this.id, this.uid, this.debateId, this.kind, this.expiresAtMs);
  final String id, uid, debateId, kind;
  final int expiresAtMs;
  String get route => '/lobby/$debateId';
  static PushDestination? parse(
      Map<String, dynamic> data, String? currentUid, int nowMs) {
    final id = data['notificationId'],
        uid = data['uid'],
        debateId = data['debateId'],
        kind = data['kind'];
    final expiry = int.tryParse('${data['expiresAtMs']}');
    if (currentUid == null ||
        uid != currentUid ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        debateId is! String ||
        !validInvitationId(debateId) ||
        !['accepted', 'turn', 'finished'].contains(kind) ||
        expiry == null ||
        expiry <= nowMs) {
      return null;
    }
    return PushDestination._(
        id, uid as String, debateId, kind as String, expiry);
  }
}

// Open the canonical protected route; startup separately checks its current route.
void openPushDestination(
    GoRouter router, PushDestination target, String? currentUid,
    {int? nowMs}) {
  if (currentUid != target.uid ||
      target.expiresAtMs <= (nowMs ?? DateTime.now().millisecondsSinceEpoch)) {
    return;
  }
  router.go(target.route);
}
