import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/firebase_environment.dart';
import 'package:verdict/firebase_options.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('database follows the build flavor', () {
    expect(currentFirestoreDatabaseId(), appFlavor == 'staging' ? 'default' : '(default)');
  });

  test('Firebase project follows the build flavor, without test-to-production fallback', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = currentFirebaseOptions();
    if (appFlavor == 'staging') {
      expect(options.projectId, 'verdict-test-1471f');
      expect(options.appId, isNot(DefaultFirebaseOptions.android.appId));
      expect(options.storageBucket, isNot(DefaultFirebaseOptions.android.storageBucket));
    } else {
      expect(options.projectId, DefaultFirebaseOptions.android.projectId);
      expect(options.appId, DefaultFirebaseOptions.android.appId);
    }
  });

  test('staging cannot silently use production configuration on another platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(currentFirebaseOptions, throwsUnsupportedError);
  }, skip: appFlavor != 'staging');
}
