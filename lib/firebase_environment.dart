import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'firebase_options.dart';
import 'firebase_options_test.dart';

FirebaseOptions currentFirebaseOptions() {
  if (appFlavor == 'staging') {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('VERDICT Test is currently configured for Android only.');
    }
    return testAndroidFirebaseOptions;
  }
  if (appFlavor != null && appFlavor != 'production') {
    throw StateError('Unknown Firebase environment: $appFlavor');
  }
  return DefaultFirebaseOptions.currentPlatform;
}

String currentFirestoreDatabaseId() => appFlavor == 'staging' ? 'default' : '(default)';
