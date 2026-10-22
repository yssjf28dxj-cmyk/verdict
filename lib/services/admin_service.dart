import 'package:verdict/firebase_session.dart';
import 'package:verdict/firestore_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminService {
  final FirebaseFirestore _db = appFirestore;
  final FirebaseFunctions _functions = appFunctions;

  Future<bool> hasMigrationAccess() async {
    final user = appAuth.currentUser;
    if (user == null) return false;

    final tokenResult = await user.getIdTokenResult(true);
    if (tokenResult.claims?['admin'] == true) {
      return true;
    }

    final userSnap = await _db.collection('users').doc(user.uid).get();
    if (userSnap.exists) {
      final data = userSnap.data();
      if ((data?['rank'] as String?)?.trim() == 'GRANDMASTER') {
        return true;
      }
    }

    final accessSnap =
        await _db.collection('admin_runtime').doc('migration_access').get();
    final accessData = accessSnap.data();
    if (accessData == null) return false;

    final enabled = accessData['enabled'] == true;
    if (!enabled) return false;

    final expiresAt = accessData['expiresAt'];
    if (expiresAt is Timestamp && !expiresAt.toDate().isAfter(DateTime.now())) {
      return false;
    }

    final allowedUids = accessData['allowedUids'];
    if (allowedUids is Iterable) {
      return allowedUids.map((e) => e.toString()).contains(user.uid);
    }

    return false;
  }

  // ПРОВЕРКА: ЯВЛЯЕТСЯ ЛИ ПОЛЬЗОВАТЕЛЬ ОСНОВАТЕЛЕМ
  Future<bool> isFounder() async {
    final user = appAuth.currentUser;
    if (user == null) return false;

    final tokenResult = await user.getIdTokenResult(true);
    if (tokenResult.claims?['admin'] == true) return true;

    final snap = await _db.collection('users').doc(user.uid).get();
    if (!snap.exists) return false;
    return (snap.data() as Map<String, dynamic>)['rank'] == 'GRANDMASTER';
  }

  // УДАЛЕНИЕ ЛЮБОГО СПОРА (ВЛАСТЬ АДМИНА)
  Future<void> deleteDebate(String debateId) async {
    if (await isFounder()) {
      final callable = _functions.httpsCallable('adminDeleteDebate');
      await callable.call({'debateId': debateId});
    }
  }

  // БАН ПОЛЬЗОВАТЕЛЯ — через Cloud Function (серверная проверка)
  Future<void> banUser(String userId) async {
    if (await isFounder()) {
      final callable = _functions.httpsCallable('adminBanUser');
      await callable.call({'userId': userId});
    }
  }

  // ОЧИСТКА ГЛОБАЛЬНОГО ХАБА — через Cloud Function (серверная проверка)
  Future<void> clearWorldChat() async {
    if (await isFounder()) {
      final callable = _functions.httpsCallable('adminClearWorldChat');
      await callable.call({});
    }
  }
}
