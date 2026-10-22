import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/firebase_session.dart';

void main() {
  test('profile switching is enabled only by the staging build flavor', () {
    expect(testProfilesEnabled, appFlavor == 'staging');
    expect(testProfiles.enabled, appFlavor == 'staging');
  });
  test('first slot preserves the default app; other slots use distinct namespaces', () {
    expect(testProfileAppName(1), '[DEFAULT]');
    final names = List.generate(6, (index) => testProfileAppName(index + 1));
    expect(names.toSet().length, 6);
    expect(names.skip(1).every((name) => name.startsWith('verdict-test-profile-')), true);
  });
}
