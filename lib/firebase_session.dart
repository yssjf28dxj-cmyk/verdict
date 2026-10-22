import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_environment.dart';
import 'services/test_profile_controller.dart';

bool get testProfilesEnabled => appFlavor == 'staging';
String testProfileAppName(int slot) => slot == 1 ? '[DEFAULT]' : 'verdict-test-profile-$slot';

final testProfiles = TestProfileController(
  enabled: testProfilesEnabled,
  prepare: _prepareTestProfile,
  load: () async => (await SharedPreferences.getInstance()).getInt('verdict.test.profile.slot'),
  save: (slot) async {
    final saved = await (await SharedPreferences.getInstance()).setInt('verdict.test.profile.slot', slot);
    if (!saved) throw StateError('Unable to save selected test profile');
  },
);

FirebaseApp get activeFirebaseApp => Firebase.app(
  testProfilesEnabled ? testProfileAppName(testProfiles.selected) : '[DEFAULT]',
);
FirebaseAuth get appAuth => FirebaseAuth.instanceFor(app: activeFirebaseApp);
FirebaseFunctions get appFunctions => FirebaseFunctions.instanceFor(app: activeFirebaseApp, region: 'us-central1');
FirebaseStorage get appStorage => FirebaseStorage.instanceFor(app: activeFirebaseApp);

Future<void> _prepareTestProfile(int slot, {required bool createAccount}) async {
  if (!testProfilesEnabled || Firebase.app().options.projectId != 'verdict-test-1471f') {
    throw StateError('Test profiles require the isolated test project');
  }
  if (slot < 1 || slot > 6) throw RangeError.range(slot, 1, 6);
  final name = testProfileAppName(slot);
  final app = Firebase.apps.any((app) => app.name == name)
      ? Firebase.app(name)
      : await Firebase.initializeApp(name: name, options: currentFirebaseOptions());
  final auth = FirebaseAuth.instanceFor(app: app);
  final restored = await auth.authStateChanges().first.timeout(const Duration(seconds: 15));
  if (!createAccount) return;
  final user = restored ?? (await auth.signInAnonymously()).user;
  if (user == null) throw StateError('Test profile sign-in failed');
  final db = FirebaseFirestore.instanceFor(app: app, databaseId: currentFirestoreDatabaseId());
  final profile = db.collection('users').doc(user.uid);
  await db.runTransaction((transaction) async {
    final snapshot = await transaction.get(profile);
    if (!snapshot.exists) {
      transaction.set(profile, {
        'name': 'Test $slot',
        'displayName': 'Test $slot',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  });
}
