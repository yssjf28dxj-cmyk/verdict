import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verdict/services/pending_challenge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const terms = {'topic': 'A useful debate', 'totalRounds': 3};
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('lost response and service recreation reuse the persisted creation ID',
      () async {
    String? first;
    await expectLater(
        PendingChallenge('alice').send(terms,
            isCurrentSession: () => true,
            submit: (payload) async {
              first = payload['clientRequestId'];
              throw StateError('Response lost after commit');
            }),
        throwsStateError);
    final retried = await PendingChallenge('alice').prepare(terms);
    expect(retried['clientRequestId'], first);
    final result = await PendingChallenge('alice').send(terms,
        isCurrentSession: () => true,
        submit: (payload) async {
          expect(payload['clientRequestId'], first);
          return {'debateId': 'same-debate'};
        });
    expect(result, 'same-debate');
    expect((await PendingChallenge('alice').prepare(terms))['clientRequestId'],
        isNot(first));
  });
  test(
      'concurrent preparations share one ID, changed terms and profiles do not',
      () async {
    final requests = await Future.wait(
        List.generate(8, (_) => PendingChallenge('alice').prepare(terms)));
    final id = requests.first['clientRequestId'];
    expect(requests.map((r) => r['clientRequestId']).toSet(), {id});
    expect((await PendingChallenge('bob').prepare(terms))['clientRequestId'],
        isNot(id));
    expect(
        (await PendingChallenge('alice')
            .prepare({...terms, 'totalRounds': 5}))['clientRequestId'],
        isNot(id));
  });
  test('map order does not change the logical intention', () async {
    final first = await PendingChallenge('alice').prepare(terms);
    final second = await PendingChallenge('alice')
        .prepare({'totalRounds': 3, 'topic': terms['topic']});
    expect(second['clientRequestId'], first['clientRequestId']);
  });
  test('logout prevents dispatch and preserves the original request', () async {
    final store = PendingChallenge('alice');
    final first = await store.prepare(terms);
    await expectLater(
        store.send(terms,
            isCurrentSession: () => false,
            submit: (_) async => fail('Network must not be contacted')),
        throwsStateError);
    expect((await store.prepare(terms))['clientRequestId'],
        first['clientRequestId']);
  });
  test(
      'late response after account switch cannot navigate or erase its request',
      () async {
    final gate = Completer<dynamic>();
    var current = true;
    final store = PendingChallenge('alice');
    final first = await store.prepare(terms);
    final entered = Completer<void>();
    final sending = store.send(terms,
        isCurrentSession: () => current,
        submit: (_) {
          entered.complete();
          return gate.future;
        });
    final expectation = expectLater(sending, throwsStateError);
    await entered.future;
    current = false;
    gate.complete({'debateId': 'old-account-debate'});
    await expectation;
    expect((await store.prepare(terms))['clientRequestId'],
        first['clientRequestId']);
  });
  test('old acknowledgement preserves a newer edited intention', () async {
    final store = PendingChallenge('alice');
    final changed = {...terms, 'topic': 'Changed topic'};
    String? nextId;
    await store.send(terms,
        isCurrentSession: () => true,
        submit: (_) async {
          nextId = (await store.prepare(changed))['clientRequestId'];
          return {'debateId': 'old-debate'};
        });
    expect((await store.prepare(changed))['clientRequestId'], nextId);
  });
  test('malformed acknowledgement never clears retry identity', () async {
    final store = PendingChallenge('alice');
    final first = await store.prepare(terms);
    for (final response in [
      null,
      {},
      {'debateId': '../unsafe'}
    ]) {
      await expectLater(
          store.send(terms,
              isCurrentSession: () => true, submit: (_) async => response),
          throwsStateError);
    }
    expect((await store.prepare(terms))['clientRequestId'],
        first['clientRequestId']);
  });
}
