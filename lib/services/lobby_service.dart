import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class LobbyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Map<String, Future<String?>> _startInFlight = {};

  int _asPositiveInt(dynamic value, int fallback) {
    final candidate =
        value is int ? value : (value is num ? value.toInt() : fallback);
    return candidate > 0 ? candidate : fallback;
  }

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

  Future<String?> _waitForDebateId(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      final snap = await ref.get();
      final data = snap.data();
      if (data == null) return null;

      final existingDebateId = (data['debateId'] ?? '').toString().trim();
      if (existingDebateId.isNotEmpty) {
        if (data['started'] != true) {
          await ref.update({'started': true});
        }
        return existingDebateId;
      }

      await Future.delayed(const Duration(milliseconds: 450));
    }

    return null;
  }

  Future<String> createLobby({
    required String creatorId,
    required String opponentId,
  }) async {
    final doc = await _db.collection('lobbies').add({
      'creatorId': creatorId,
      'opponentId': opponentId,
      'creatorTime': null,
      'opponentTime': null,
      'creatorReady': false,
      'opponentReady': false,
      'started': false,
      'debateId': null,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  Future<void> chooseTime({
    required String lobbyId,
    required String userId,
    required int seconds,
  }) async {
    final ref = _db.collection('lobbies').doc(lobbyId);
    final snap = await ref.get();
    final data = snap.data();

    if (data == null) return;

    if (data['creatorId'] == userId) {
      await ref.update({'creatorTime': seconds});
    } else if (data['opponentId'] == userId) {
      await ref.update({'opponentTime': seconds});
    }
  }

  Future<void> setReady({
    required String lobbyId,
    required String userId,
  }) async {
    final ref = _db.collection('lobbies').doc(lobbyId);
    final snap = await ref.get();
    final data = snap.data();

    if (data == null) return;

    if (data['creatorId'] == userId) {
      await ref.update({'creatorReady': true});
    } else if (data['opponentId'] == userId) {
      await ref.update({'opponentReady': true});
    }
  }

  Future<String?> startDebate(String lobbyId) async {
    final existingInFlight = _startInFlight[lobbyId];
    if (existingInFlight != null) {
      return existingInFlight;
    }

    final inFlight = _startDebateInternal(lobbyId);
    _startInFlight[lobbyId] = inFlight;
    try {
      return await inFlight;
    } finally {
      final current = _startInFlight[lobbyId];
      if (identical(current, inFlight)) {
        _startInFlight.remove(lobbyId);
      }
    }
  }

  Future<String?> _startDebateInternal(String lobbyId) async {
    final ref = _db.collection('lobbies').doc(lobbyId);
    final txPlan = await _db.runTransaction<Map<String, dynamic>>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) {
        return {'action': 'missing'};
      }

      final existingDebateId = (data['debateId'] ?? '').toString().trim();
      if (existingDebateId.isNotEmpty) {
        if (data['started'] != true || data['creatingDebate'] == true) {
          tx.update(ref, {
            'started': true,
            'creatingDebate': false,
          });
        }
        return {
          'action': 'existing',
          'debateId': existingDebateId,
        };
      }

      if (data['creatingDebate'] == true) {
        return {'action': 'wait'};
      }

      final creatorTime = _asPositiveInt(data['creatorTime'], 60);
      final opponentTime = _asPositiveInt(data['opponentTime'], 60);
      final finalTime = ((creatorTime + opponentTime) / 2).round();
      final fighter2Id = (data['opponentId'] ?? '').toString().trim();

      tx.update(ref, {
        'creatingDebate': true,
        'createDebateRequestedAt': FieldValue.serverTimestamp(),
      });

      return {
        'action': 'create',
        'durationSeconds': finalTime,
        'fighter2Id': fighter2Id,
      };
    });

    final action = (txPlan['action'] ?? '').toString();
    if (action == 'missing') return null;
    if (action == 'existing') {
      return (txPlan['debateId'] ?? '').toString().trim();
    }
    if (action == 'wait') {
      return _waitForDebateId(ref);
    }

    final int durationSeconds = _asPositiveInt(txPlan['durationSeconds'], 60);
    final String fighter2Id = (txPlan['fighter2Id'] ?? '').toString().trim();
    final callable = _functions.httpsCallable(
      'createDebate',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    try {
      final res = await callable.call({
        'topic': 'Private lobby debate',
        'durationSeconds': durationSeconds,
        'totalRounds': 3,
        'creationMode': fighter2Id.isNotEmpty ? 'direct_invite' : 'public_feed',
        'visibilityMode': fighter2Id.isNotEmpty ? 'private' : 'public',
        'languageCode': 'ru',
        'region': 'global',
        'invitedUserId': fighter2Id,
      });

      final debateId = _extractDebateId(res.data);
      if (debateId.isEmpty) {
        await ref.update({'creatingDebate': false});
        return _waitForDebateId(ref);
      }

      await ref.update({
        'started': true,
        'debateId': debateId,
        'creatingDebate': false,
      });
      return debateId;
    } catch (_) {
      try {
        await ref.update({'creatingDebate': false});
      } catch (_) {}
      return _waitForDebateId(ref);
    }
  }
}
