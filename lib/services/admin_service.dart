import 'package:verdict/firebase_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminService {
  final FirebaseAuth _auth = appAuth;
  final FirebaseFunctions _functions = appFunctions;

  // Administrative authority is decided by authenticated server policy, never
  // by a gameplay rank or a client-readable emergency-access document.
  Future<Map<String, dynamic>> _administrativeAccess() async {
    if (_auth.currentUser == null) return const {};
    try {
      final response = await _functions
          .httpsCallable(
            'getAdministrativeAccess',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call();
      final payload = response.data;
      return payload is Map ? Map<String, dynamic>.from(payload) : const {};
    } catch (error) {
      debugPrint('Administrative access could not be verified: $error');
      return const {};
    }
  }

  Future<bool> hasMigrationAccess() async =>
      (await _administrativeAccess())['migration'] == true;

  Future<bool> isFounder() async =>
      (await _administrativeAccess())['admin'] == true;

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
