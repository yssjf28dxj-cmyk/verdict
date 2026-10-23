import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../firebase_session.dart';
import '../firestore_database.dart';
import '../utils/invitation_links.dart';

class MessageReactionView {
  const MessageReactionView(
      {this.strongCount = 0,
      this.sourceCount = 0,
      this.strong = false,
      this.source = false,
      this.strongRevision = 0,
      this.sourceRevision = 0,
      this.canReact = false});
  final int strongCount, sourceCount, strongRevision, sourceRevision;
  final bool strong, source, canReact;
}

class MessageReactionService {
  MessageReactionService(this.debateId, this.messageId)
      : _uid = appAuth.currentUser?.uid,
        _db = appFirestore,
        _functions = appFunctions {
    if (!validInvitationId(debateId) ||
        !validInvitationId(messageId) ||
        _uid == null) {
      throw StateError('Invalid reaction session');
    }
  }
  final String debateId, messageId;
  final String? _uid;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  void _check() {
    if (_uid != appAuth.currentUser?.uid) throw StateError('Session changed');
  }

  Stream<MessageReactionView> watch() {
    final parent = _db.collection('debates').doc(debateId);
    final message = parent.collection('messages').doc(messageId);
    late StreamController<MessageReactionView> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    Map<String, dynamic>? own, debate;
    QuerySnapshot<Map<String, dynamic>>? tallies;
    bool terminal = false;
    void emit() {
      if (terminal) return;
      if (own == null || debate == null || tallies == null) return;
      try {
        _check();
        int count(String kind) => tallies!.docs.fold(0, (total, doc) {
              final value = doc.data()[kind];
              return total + (value is int && value > 0 ? value : 0);
            });
        Map state(String kind) =>
            own![kind] is Map ? own![kind] as Map : const {};
        int revision(String kind) =>
            state(kind)['revision'] is int ? state(kind)['revision'] as int : 0;
        final fighter = [
              'fighter1',
              'fighter2',
              'creatorId',
              'invitedUserId',
              'opponentId'
            ].any((key) => debate![key] == _uid) ||
            (debate!['invitedUserIds'] is List &&
                (debate!['invitedUserIds'] as List).contains(_uid));
        controller.add(MessageReactionView(
            strongCount: count('strong'),
            sourceCount: count('source'),
            strong: state('strong')['active'] == true,
            source: state('source')['active'] == true,
            strongRevision: revision('strong'),
            sourceRevision: revision('source'),
            canReact:
                !fighter && ['active', 'live'].contains(debate!['status'])));
      } catch (error, stack) {
        terminal = true;
        controller.addError(error, stack);
      }
    }

    void fail(Object error, StackTrace stack) {
      terminal = true;
      controller.addError(error, stack);
    }

    controller = StreamController<MessageReactionView>(onListen: () {
      subscriptions.add(parent.snapshots().listen((snapshot) {
        if (!snapshot.exists) {
          fail(StateError('Battle unavailable'), StackTrace.current);
          return;
        }
        debate = snapshot.data();
        emit();
      }, onError: fail));
      subscriptions.add(message
          .collection('reactions')
          .doc(_uid!)
          .snapshots()
          .listen((snapshot) {
        own = snapshot.data() ?? {};
        emit();
      }, onError: fail));
      subscriptions.add(message
          .collection('reaction_tallies')
          .limit(16)
          .snapshots()
          .listen((snapshot) {
        tallies = snapshot;
        emit();
      }, onError: fail));
    }, onCancel: () async {
      await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()));
      unawaited(controller.close());
    });
    return controller.stream;
  }

  Future<void> set(
      String kind, bool active, int revision, String requestId) async {
    _check();
    await _functions
        .httpsCallable('setMessageReaction',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
        .call({
      'debateId': debateId,
      'messageId': messageId,
      'kind': kind,
      'active': active,
      'expectedRevision': revision,
      'clientRequestId': requestId
    });
    _check();
  }
}
