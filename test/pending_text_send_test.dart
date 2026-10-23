import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
// Test-only SDK host initialization; no backend or credentials are used.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verdict/services/pending_text_send.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
      StandardMessageCodec());
  final calls = <Map<dynamic, dynamic>>[];
  Future<List<Object?>> Function(Map<dynamic, dynamic>)? respond;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    respond = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
      final arguments = (message as List).single as Map;
      expect(arguments['functionName'], 'sendDebateMessage');
      final payload = arguments['parameters'] as Map;
      calls.add(Map.of(payload));
      return respond == null
          ? [
              {'ok': true, 'messageId': 'accepted-id'}
            ]
          : await respond!(payload);
    });
  });
  Future<void> send(PendingTextSend store,
          {String text = 'Argument',
          int round = 1,
          bool Function()? current}) =>
      store.send(text, round,
          callable:
              FirebaseFunctions.instance.httpsCallable('sendDebateMessage'),
          isCurrentSession: current ?? () => true);
  List<Object?> rejection(String code, [Object? details]) => [
        'firebase_functions',
        code,
        {'code': code, 'message': code, 'additionalData': details}
      ];

  test(
      'recreated service restores original ID, text and round after lost response',
      () async {
    final first =
        await PendingTextSend('alice', 'battle').prepare('Argument', 1);
    final persisted = await SharedPreferences.getInstance();
    final disk = {
      for (final key in persisted.getKeys()) key: persisted.get(key)!
    };
    SharedPreferences.setMockInitialValues(
        disk); // Recreate the plugin cache from persisted values.
    final restarted = PendingTextSend('alice', 'battle');
    final retry = await restarted.prepare('Argument', 2);
    expect(retry.id, first.id);
    expect(retry.round, 1);
    await restarted.confirmed(retry);
    final next = await restarted.prepare('Argument', 2);
    expect(next.id, isNot(first.id));
    expect(next.round, 2);
  });
  test(
      'identity and debate isolation; late acknowledgement preserves new draft',
      () async {
    final store = PendingTextSend('alice', 'battle');
    final old = await store.prepare('Old', 1);
    final next = await store.prepare('New', 1);
    await store.confirmed(old);
    expect((await store.load())!.id, next.id);
    expect(await PendingTextSend('bob', 'battle').load(), isNull);
    expect(await PendingTextSend('alice', 'other').load(), isNull);
  });
  test('concurrent service instances allocate only one logical request',
      () async {
    final requests = await Future.wait(List.generate(
        8, (_) => PendingTextSend('alice', 'battle').prepare('Same', 1)));
    expect(requests.map((r) => r.id).toSet().length, 1);
  });

  test(
      'SDK callable sends persisted identity and retries lost response unchanged',
      () async {
    final store = PendingTextSend('alice', 'battle');
    respond = (payload) async {
      final saved = await store.load();
      expect(saved!.id, payload['clientRequestId']);
      expect(payload['expectedRound'], 1);
      expect(payload['expectedSenderId'], 'alice');
      expect(payload['debateId'], 'battle');
      expect(payload['text'], 'Argument');
      return calls.length == 1
          ? rejection('deadline-exceeded')
          : [
              {'ok': true, 'messageId': 'accepted-id'}
            ];
    };
    await send(store);
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(await store.load(), isNull);
  });
  test(
      'ambiguous commit then access/auth denial retains original identity for recovery',
      () async {
    final store = PendingTextSend('alice', 'battle');
    respond = (_) async => rejection('deadline-exceeded');
    await expectLater(send(store), throwsA(isA<FirebaseFunctionsException>()));
    final original = (await store.load())!;
    for (final code in [
      'permission-denied',
      'unauthenticated',
      'resource-exhausted'
    ]) {
      respond = (_) async => rejection(code);
      await expectLater(
          send(store), throwsA(isA<FirebaseFunctionsException>()));
      expect((await store.load())!.id, original.id);
    }
    respond = null;
    await send(PendingTextSend('alice', 'battle'), round: 2);
    expect(calls.last['clientRequestId'], original.id);
    expect(calls.last['expectedRound'], 1);
  });
  test(
      'only explicit uncommitted rejection releases stale identity for a new attempt',
      () async {
    final store = PendingTextSend('alice', 'battle');
    final original = await store.prepare('Argument', 1);
    respond = (_) async =>
        rejection('failed-precondition', {'reason': 'TURN_TIME_EXPIRED'});
    await expectLater(
        send(store, round: 2), throwsA(isA<FirebaseFunctionsException>()));
    expect((await store.load())!.id, original.id);
    respond = (_) async => rejection('failed-precondition',
        {'reason': 'TURN_TIME_EXPIRED', 'textRequestUncommitted': true});
    await expectLater(
        send(store, round: 2), throwsA(isA<FirebaseFunctionsException>()));
    expect(calls.last['expectedRound'], 1);
    expect(await store.load(), isNull);
    respond = null;
    await send(store, round: 2);
    expect(calls.last['clientRequestId'], isNot(original.id));
    expect(calls.last['expectedRound'], 2);
  });
  test('logout before retry stops network call and preserves identity',
      () async {
    final store = PendingTextSend('alice', 'battle');
    var current = true;
    respond = (_) async {
      current = false;
      return rejection('unavailable');
    };
    await expectLater(send(store, current: () => current),
        throwsA(isA<FirebaseFunctionsException>()));
    expect(calls.length, 1);
    expect(await store.load(), isNotNull);
    expect(await PendingTextSend('bob', 'battle').load(), isNull);
  });
  test(
      'late acknowledgement and restore do not erase or resurrect edited drafts',
      () async {
    final controller = TextEditingController(text: 'Argument');
    final tracker = TextDraftTracker(controller);
    final submitted = tracker.revision;
    final entered = Completer<void>();
    final reply = Completer<List<Object?>>();
    respond = (_) {
      entered.complete();
      return reply.future;
    };
    final sending = send(PendingTextSend('alice', 'battle'));
    await entered.future;
    controller.text = 'New';
    controller.text = 'Argument';
    reply.complete([
      {'ok': true, 'messageId': 'accepted-id'}
    ]);
    await sending;
    tracker.clearIfUnchanged(submitted);
    expect(controller.text, 'Argument');
    controller.clear();
    final restoreRevision = tracker.revision;
    controller.text = 'User changed mind';
    controller.clear();
    tracker.restoreIfUnchanged(restoreRevision, 'Old persisted text');
    expect(controller.text, isEmpty);
    tracker.dispose();
    controller.dispose();
  });
  test('concurrent confirmation cannot delete a newer saved request', () async {
    for (var i = 0; i < 10; i++) {
      final first = PendingTextSend('alice', 'race-$i');
      final old = await first.prepare('Old', 1);
      await Future.wait([
        first.confirmed(old),
        PendingTextSend('alice', 'race-$i').prepare('New', 1)
      ]);
      expect((await first.load())!.text, 'New');
    }
  });
  test('invalid acknowledgement does not clear the persistent request',
      () async {
    final store = PendingTextSend('alice', 'battle');
    respond = (_) async => [
          {'ok': true}
        ];
    await expectLater(send(store), throwsStateError);
    expect(await store.load(), isNotNull);
  });
}
