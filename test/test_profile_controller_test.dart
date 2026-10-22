import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/services/test_profile_controller.dart';

void main() {
  test('switching slots preserves each previously prepared identity', () async {
    final identities = <int, String>{1: 'original-guest'};
    int? saved;
    final controller = TestProfileController(
      enabled: true,
      load: () async => saved,
      save: (slot) async => saved = slot,
      prepare: (slot, {required createAccount}) async {
        if (createAccount) identities.putIfAbsent(slot, () => 'guest-$slot');
      },
    );
    for (var slot = 2; slot <= 6; slot++) {
      await controller.switchTo(slot);
    }
    await controller.switchTo(1);
    expect(identities[controller.selected], 'original-guest');
    expect(identities.length, 6);
    await controller.switchTo(2);
    expect(identities[controller.selected], 'guest-2');
    expect(identities.length, 6);
  });

  test('restoring selection never creates another guest identity', () async {
    final requests = <String>[];
    final controller = TestProfileController(
      enabled: true,
      load: () async => 4,
      save: (_) async => fail('Restore must not change storage'),
      prepare: (slot, {required createAccount}) async => requests.add('$slot:$createAccount'),
    );
    await controller.restore();
    expect(controller.selected, 4);
    expect(requests, ['4:false']);
  });

  test('production cannot prepare, load, save or switch test profiles', () async {
    final controller = TestProfileController(
      enabled: false,
      load: () async => throw StateError('Must not load'),
      save: (_) async => throw StateError('Must not save'),
      prepare: (_, {required createAccount}) async => throw StateError('Must not prepare'),
    );
    await controller.restore();
    expect(controller.selected, 1);
    await expectLater(controller.switchTo(2), throwsStateError);
  });

  test('failed sign-in retains the old profile and never persists the target', () async {
    var saved = false;
    final controller = TestProfileController(
      enabled: true,
      load: () async => null,
      save: (_) async => saved = true,
      prepare: (_, {required createAccount}) async => throw StateError('Offline'),
    );
    await expectLater(controller.switchTo(2), throwsStateError);
    expect(controller.selected, 1);
    expect(controller.busy, false);
    expect(saved, false);
  });

  test('concurrent taps cannot select an incompletely prepared session', () async {
    final ready = Completer<void>();
    final requests = <int>[];
    final controller = TestProfileController(
      enabled: true,
      load: () async => null,
      save: (_) async {},
      prepare: (slot, {required createAccount}) async {
        requests.add(slot);
        await ready.future;
      },
    );
    final switching = controller.switchTo(2);
    expect(controller.selected, 1);
    expect(controller.busy, true);
    await controller.switchTo(3);
    expect(requests, [2]);
    ready.complete();
    await switching;
    expect(controller.selected, 2);
    expect(controller.busy, false);
  });

  test('failed persistence retains original session', () async {
    final controller = TestProfileController(
      enabled: true,
      load: () async => null,
      save: (_) async => throw StateError('Disk full'),
      prepare: (_, {required createAccount}) async {},
    );
    await expectLater(controller.switchTo(2), throwsStateError);
    expect(controller.selected, 1);
    expect(controller.busy, false);
  });

  test('slots outside 1–6 are rejected; tapping current slot does nothing', () async {
    var prepared = 0;
    final controller = TestProfileController(
      enabled: true,
      load: () async => null,
      save: (_) async {},
      prepare: (_, {required createAccount}) async => prepared++,
    );
    await expectLater(controller.switchTo(0), throwsRangeError);
    await expectLater(controller.switchTo(7), throwsRangeError);
    await controller.switchTo(1);
    expect(prepared, 0);
  });
}
