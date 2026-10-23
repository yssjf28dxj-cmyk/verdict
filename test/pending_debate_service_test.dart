import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/services/pending_debate_service.dart';

void main() {
  test(
      'revoked access clears the pending banner without an unhandled stream error',
      () async {
    final updates = StreamController<Map<String, dynamic>?>();
    final service = PendingDebateService.forTesting((_) => updates.stream);
    service.startWatching('private');
    expect(service.isWatching, isTrue);
    updates.addError(FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied'));
    await Future<void>.delayed(Duration.zero);
    expect(service.isWatching, isFalse);
    expect(service.activatedDebateId, isNull);
    service.dispose();
    await updates.close();
  });
  test('deleted invitation clears a pending watch instead of waiting forever',
      () async {
    final updates = StreamController<Map<String, dynamic>?>();
    final service = PendingDebateService.forTesting((_) => updates.stream);
    service.startWatching('removed');
    updates.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(service.watchedDebateId, isNull);
    service.dispose();
    await updates.close();
  });
  test('a permitted invitation still announces the battle once when it starts',
      () async {
    final updates = StreamController<Map<String, dynamic>?>();
    final service = PendingDebateService.forTesting((_) => updates.stream);
    service.startWatching('allowed', topic: 'Topic');
    updates.add({'status': 'active'});
    await Future<void>.delayed(Duration.zero);
    expect(service.activatedDebateId, 'allowed');
    expect(service.activatedTopic, 'Topic');
    service.stopWatching();
    expect(service.activatedDebateId, isNull);
    service.dispose();
    await updates.close();
  });
}
