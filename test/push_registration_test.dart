import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/services/push_registration_controller.dart';
import 'package:verdict/utils/push_destination.dart';

class Harness {
  String? uid = 'alice';
  bool enabled = false,
      permitted = true,
      bound = false,
      failRegister = false,
      failRetire = false;
  int prompts = 0;
  final log = <String>[];
  Completer<bool>? readBarrier;
  late final controller = PushRegistrationController(
      currentUid: () => uid,
      installationKey: () async => 'a' * 64,
      readEnabled: (user) async {
        log.add('read:$user');
        return readBarrier == null ? enabled : await readBarrier!.future;
      },
      configure: (user, value) async {
        log.add('configure:$user:$value');
        enabled = value;
      },
      register: (user, token, key) async {
        log.add('register:$user');
        if (failRegister) throw StateError('Lost acknowledgement');
      },
      unregister: (user, key) async {
        log.add('unregister:$user');
        if (failRetire) throw StateError('Offline');
      },
      hasPermission: () async => permitted,
      requestPermission: () async {
        prompts++;
        return permitted;
      },
      setAutoInit: (value) async {
        log.add('auto:$value');
      },
      getToken: () async => 'device-token',
      deleteToken: () async {
        log.add('deleteToken');
      },
      readBinding: () async => bound,
      writeBinding: (value) async {
        bound = value;
        log.add('bound:$value');
      });
}

void main() {
  test('startup does not ask permission or register an opted-out account',
      () async {
    final h = Harness();
    await h.controller.sync();
    expect(h.prompts, 0);
    expect(h.log.where((v) => v.startsWith('register')), isEmpty);
  });
  test('permission denial neither opts in nor binds a device', () async {
    final h = Harness()..permitted = false;
    await expectLater(h.controller.enable(), throwsStateError);
    expect(h.enabled, false);
    expect(h.bound, false);
    expect(h.prompts, 1);
  });
  test(
      'explicit opt-in binds and disabling unregisters before losing the binding marker',
      () async {
    final h = Harness();
    await h.controller.enable();
    expect(h.enabled, true);
    expect(h.bound, true);
    await h.controller.disable();
    expect(h.enabled, false);
    expect(h.bound, false);
    expect(h.log.indexOf('unregister:alice'),
        lessThan(h.log.lastIndexOf('bound:false')));
  });
  test('a lost registration acknowledgement preserves cleanup responsibility',
      () async {
    final h = Harness()..failRegister = true;
    await expectLater(h.controller.enable(), throwsStateError);
    expect(h.enabled, false);
    expect(h.bound, true);
    await h.controller.retire();
    expect(h.log, contains('unregister:alice'));
    expect(h.bound, false);
  });
  test(
      'account change during a network read cannot register the previous identity',
      () async {
    final h = Harness()..enabled = true;
    final barrier = Completer<bool>();
    h.readBarrier = barrier;
    final sync = h.controller.sync();
    await Future<void>.delayed(Duration.zero);
    h.uid = 'bob';
    barrier.complete(true);
    await expectLater(sync, throwsStateError);
    expect(h.log.where((v) => v.startsWith('register')), isEmpty);
    h.readBarrier = null;
    await h.controller.sync();
    expect(h.log, contains('register:bob'));
  });
  test(
      'switch cleanup failures remain visible and a later retry is not poisoned',
      () async {
    final h = Harness()
      ..bound = true
      ..failRetire = true;
    await expectLater(h.controller.retire(), throwsStateError);
    expect(h.bound, true);
    h.failRetire = false;
    await h.controller.retire();
    expect(h.bound, false);
  });
  test('serial enable then retire cannot leave a late registration behind',
      () async {
    final h = Harness();
    await Future.wait([h.controller.enable(), h.controller.retire()]);
    expect(h.bound, false);
    expect(h.log.indexOf('register:alice'),
        lessThan(h.log.indexOf('unregister:alice')));
  });
  test(
      'token refresh queued during opt-in cannot retire a registration that just completed',
      () async {
    final h = Harness();
    await Future.wait([
      h.controller.enable(),
      h.controller.sync(refreshedToken: 'device-token')
    ]);
    expect(h.bound, true);
    expect(h.log.where((value) => value == 'register:alice').length, 1);
    expect(h.log.where((value) => value.startsWith('unregister')), isEmpty);
  });
  test(
      'resuming with a valid existing registration does not unregister it again',
      () async {
    final h = Harness();
    await h.controller.enable();
    await h.controller.sync();
    expect(h.bound, true);
    expect(h.log.where((value) => value == 'register:alice').length, 1);
    expect(h.log.where((value) => value.startsWith('unregister')), isEmpty);
  });
  test(
      'revoking OS permission while backgrounded retires the binding on resume',
      () async {
    final h = Harness();
    await h.controller.enable();
    h.permitted = false;
    await h.controller.sync();
    expect(h.bound, false);
    expect(h.log, contains('unregister:alice'));
    expect(h.prompts, 1);
  });
  test('signed-out startup retires a previously bound native token', () async {
    final h = Harness()
      ..uid = null
      ..bound = true;
    await h.controller.sync();
    expect(h.log, contains('deleteToken'));
    expect(h.bound, false);
  });
  final data = {
    'notificationId': 'a' * 64,
    'uid': 'alice',
    'debateId': 'battle',
    'kind': 'turn',
    'expiresAtMs': '2000'
  };
  test(
      'notification locators open only the matching current account through the protected lobby',
      () {
    expect(PushDestination.parse(data, 'alice', 1000)?.route, '/lobby/battle');
    expect(PushDestination.parse(data, 'bob', 1000), isNull);
    expect(PushDestination.parse(data, null, 1000), isNull);
  });
  test('expired and malformed destinations cannot become arbitrary navigation',
      () {
    expect(PushDestination.parse(data, 'alice', 2000), isNull);
    for (final invalid in [
      {'debateId': '../secret'},
      {'kind': 'https://evil.test'},
      {'notificationId': 'x'},
      {'expiresAtMs': 'NaN'}
    ]) {
      expect(
          PushDestination.parse({...data, ...invalid}, 'alice', 1000), isNull);
    }
  });
}
