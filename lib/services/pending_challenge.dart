import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/pending_message_request.dart';

/// Persist the creation intention before dispatch, separately for every account.
class PendingChallenge {
  PendingChallenge(this.uid);
  final String uid;
  String get _key => 'pending_challenge_v1:${Uri.encodeComponent(uid)}';
  static final Map<String, Future<void>> _operations = {};

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    final previous = _operations[_key] ?? Future<void>.value();
    final done = Completer<void>();
    _operations[_key] = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
      if (identical(_operations[_key], done.future)) _operations.remove(_key);
    }
  }

  Future<Map<String, dynamic>> prepare(Map<String, dynamic> terms) =>
      _exclusive(() async {
        final sorted = Map<String, dynamic>.fromEntries(
            terms.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
        final signature = jsonEncode(sorted);
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final raw = prefs.getString(_key);
        if (raw != null) {
          final saved = jsonDecode(raw) as Map<String, dynamic>;
          if (saved['terms'] == signature && saved['id'] is String) {
            return {...sorted, 'clientRequestId': saved['id']};
          }
        }
        final id = PendingMessageRequest().forText(signature).id;
        if (!await prefs.setString(
            _key, jsonEncode({'terms': signature, 'id': id}))) {
          throw StateError('Cannot preserve challenge request');
        }
        return {...sorted, 'clientRequestId': id};
      });

  Future<String> send(
    Map<String, dynamic> terms, {
    required Future<dynamic> Function(Map<String, dynamic>) submit,
    required bool Function() isCurrentSession,
  }) async {
    final request = await prepare(terms);
    if (!isCurrentSession()) throw StateError('Session changed');
    final result = await submit(request);
    if (!isCurrentSession()) throw StateError('Session changed');
    final id = result is Map ? result['debateId'] : null;
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw StateError('Missing challenge acknowledgement');
    }
    await _exclusive(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_key);
      if (raw != null &&
          (jsonDecode(raw) as Map)['id'] == request['clientRequestId']) {
        if (!await prefs.remove(_key)) {
          throw StateError('Cannot clear challenge request');
        }
      }
    });
    if (!isCurrentSession()) throw StateError('Session changed');
    return id;
  }
}
