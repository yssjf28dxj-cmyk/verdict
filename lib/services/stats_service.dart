import 'package:verdict/firestore_database.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class StatsService {
  final FirebaseFirestore _db = appFirestore;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Главный метод: Обработка финала битвы
  // Этот метод должен вызываться, когда таймер доходит до 0 в последнем раунде
  Future<void> finalizeBattle(String debateId) async {
    try {
      final callable = _functions.httpsCallable('advanceRoundOrFinish');
      await callable.call({'debateId': debateId});
    } catch (e) {
      debugPrint('STATS ERROR: $e');
    }
  }

  // Глобальный топ лидеров (Leaderboard)
  Stream<QuerySnapshot> getTopFighters() {
    return _db
        .collection('users')
        .orderBy('rating', descending: true)
        .limit(50)
        .snapshots();
  }

  // Получение статистики конкретного игрока
  Future<Map<String, dynamic>?> getUserStats(String uid) async {
    DocumentSnapshot snap = await _db.collection('users').doc(uid).get();
    return snap.exists ? snap.data() as Map<String, dynamic> : null;
  }
}
