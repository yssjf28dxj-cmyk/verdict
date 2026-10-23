import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/pending_message_request.dart';

class TextSendRequest {
  TextSendRequest(this.id, this.text, this.round);
  final String id;
  final String text;
  final int round;
  Map<String, dynamic> get json => {'id': id, 'text': text, 'round': round};
}

/// Persist before dispatch; a new process must retry the original intention.
/// Scope by identity and debate so test profiles never share pending text.
class PendingTextSend {
  PendingTextSend(this.uid, this.debateId);
  final String uid;
  final String debateId;
  String get _key =>
      'pending_text_v1:${Uri.encodeComponent(uid)}:${Uri.encodeComponent(debateId)}';
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

  Future<TextSendRequest?> load() => _exclusive(_load);
  Future<TextSendRequest?> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return TextSendRequest(
        data['id'] as String, data['text'] as String, data['round'] as int);
  }

  Future<TextSendRequest> prepare(String text, int round) =>
      _exclusive(() async {
        final normalized = text.trim();
        final old = await _load();
        // Editing and sending different text is an explicit new intention, not a retry.
        if (old?.text == normalized) return old!;
        final request = TextSendRequest(
            PendingMessageRequest().forText(normalized).id, normalized, round);
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_key, jsonEncode(request.json))) {
          throw StateError('Cannot persist pending message');
        }
        return request;
      });

  Future<void> confirmed(TextSendRequest request) => _exclusive(() async {
        if ((await _load())?.id != request.id) return;
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.remove(_key)) {
          throw StateError('Cannot clear pending message');
        }
      });
  Future<void> send(
    String text,
    int round, {
    required HttpsCallable callable,
    required bool Function() isCurrentSession,
  }) async {
    final request = await prepare(text, round);
    Future<void> invoke() async {
      if (!isCurrentSession()) {
        throw FirebaseFunctionsException(
            code: 'cancelled', message: 'Session changed');
      }
      final result = await callable.call(<String, dynamic>{
        'debateId': debateId,
        'text': request.text,
        'clientRequestId': request.id,
        'expectedRound': request.round,
        'expectedSenderId': uid,
      });
      final data = result.data;
      if (data is! Map ||
          data['ok'] != true ||
          data['messageId'] is! String ||
          (data['messageId'] as String).isEmpty) {
        throw StateError('Missing message acknowledgement');
      }
    }

    try {
      try {
        await invoke();
      } on FirebaseFunctionsException catch (error) {
        if (!['internal', 'unavailable', 'deadline-exceeded']
            .contains(error.code)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await invoke();
      }
    } on FirebaseFunctionsException catch (error) {
      // Authorization errors say nothing about a previous ambiguous commit.
      // Only the new server can prove that this identity was never committed.
      final details = error.details;
      if (error.code == 'failed-precondition' &&
          details is Map &&
          details['textRequestUncommitted'] == true) {
        await confirmed(request);
      }
      rethrow;
    }
    await confirmed(request);
  }
}

/// Track edits rather than text equality (A -> B -> A is still a new draft).
class TextDraftTracker {
  TextDraftTracker(this.controller) {
    _text = controller.text;
    controller.addListener(_changed);
  }
  final TextEditingController controller;
  late String _text;
  int revision = 0;
  void _changed() {
    if (_text != controller.text) {
      _text = controller.text;
      revision++;
    }
  }

  void clearIfUnchanged(int submittedRevision) {
    if (revision == submittedRevision) controller.clear();
  }

  void restoreIfUnchanged(int initialRevision, String text) {
    if (revision == initialRevision && controller.text.isEmpty) {
      controller.text = text;
    }
  }

  void dispose() => controller.removeListener(_changed);
}
