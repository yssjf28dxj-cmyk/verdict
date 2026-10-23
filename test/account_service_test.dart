import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/services/account_service.dart';

class TestCredential extends Fake implements UserCredential {
  TestCredential(this.user);
  @override
  final User? user;
}

class TestProvider extends Fake implements UserInfo {
  TestProvider(this.providerId);
  @override
  final String providerId;
}

class TestUser extends Fake implements User {
  TestUser(this.uid, {this.isAnonymous = true});
  @override
  final String uid;
  @override
  bool isAnonymous;
  @override
  List<UserInfo> get providerData =>
      credentials.map((c) => TestProvider(c.providerId)).toList();
  @override
  bool get emailVerified => false;
  final credentials = <AuthCredential>[];
  FirebaseAuthException? linkError;
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    credentials.add(credential);
    if (linkError != null) throw linkError!;
    isAnonymous = false;
    return TestCredential(this);
  }
}

class TestAuth extends Fake implements FirebaseAuth {
  TestAuth(this.currentUser);
  @override
  User? currentUser;
  @override
  Stream<User?> userChanges() => Stream.value(currentUser);
  int logins = 0;
  @override
  Future<UserCredential> signInWithEmailAndPassword(
      {required String email, required String password}) async {
    logins++;
    currentUser = TestUser('restored', isAnonymous: false);
    return TestCredential(currentUser);
  }
}

void main() {
  test('Google stays unavailable until provider configuration is ready',
      () async {
    final user = TestUser('guest');
    var picks = 0;
    final service = AccountService(
        auth: TestAuth(user),
        googleEnabled: false,
        googlePicker: () async {
          picks++;
          return null;
        });
    await expectLater(
        service.linkGoogle(),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'operation-not-allowed')));
    expect(picks, 0);
    expect(user.isAnonymous, isTrue);
  });
  test('email links to the existing guest UID without a separate sign-in',
      () async {
    final user = TestUser('fighter-original');
    final auth = TestAuth(user);
    final result = await AccountService(auth: auth)
        .linkEmail(' fighter@example.test ', 'safe-password');
    expect(result.user!.uid, 'fighter-original');
    expect(auth.currentUser, same(user));
    expect(user.isAnonymous, isFalse);
    expect(user.credentials.single.providerId, 'password');
    expect(auth.logins, 0);
  });
  for (final code in [
    'credential-already-in-use',
    'email-already-in-use',
    'network-request-failed'
  ]) {
    test('$code leaves the guest signed in and never falls back to login',
        () async {
      final user = TestUser('guest')
        ..linkError = FirebaseAuthException(code: code);
      final auth = TestAuth(user);
      await expectLater(
          AccountService(auth: auth)
              .linkEmail('used@example.test', 'safe-password'),
          throwsA(isA<FirebaseAuthException>()
              .having((e) => e.code, 'code', code)));
      expect(auth.currentUser, same(user));
      expect(user.isAnonymous, isTrue);
      expect(auth.logins, 0);
    });
  }
  test('Google picker cancellation does not alter guest credentials', () async {
    final user = TestUser('guest');
    final service =
        AccountService(auth: TestAuth(user), googlePicker: () async => null);
    expect(await service.linkGoogle(), isNull);
    expect(user.credentials, isEmpty);
    expect(user.isAnonymous, isTrue);
  });
  test(
      'provider failure releases the operation lock so email can save the same guest',
      () async {
    final user = TestUser('guest');
    final auth = TestAuth(user);
    final service = AccountService(
        auth: auth,
        googlePicker: () async {
          throw FirebaseAuthException(code: 'network-request-failed');
        });
    await expectLater(
        service.linkGoogle(), throwsA(isA<FirebaseAuthException>()));
    final saved =
        await service.linkEmail('fighter@example.test', 'safe-password');
    expect(saved.user!.uid, 'guest');
    expect(auth.logins, 0);
  });
  test('Google links to the same guest with no separate Firebase login',
      () async {
    final user = TestUser('guest');
    final auth = TestAuth(user);
    final service = AccountService(
        auth: auth,
        googlePicker: () async =>
            GoogleAuthProvider.credential(idToken: 'emulated-token'));
    expect((await service.linkGoogle())!.user!.uid, 'guest');
    expect(user.credentials.single.providerId, 'google.com');
    expect(auth.logins, 0);
  });
  test('a session changed while Google is open cannot link the previous guest',
      () async {
    final original = TestUser('old');
    final auth = TestAuth(original);
    final picker = Completer<AuthCredential?>();
    final service =
        AccountService(auth: auth, googlePicker: () => picker.future);
    final link = service.linkGoogle();
    final rejected = expectLater(
        link,
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'guest-session-changed')));
    auth.currentUser = TestUser('new');
    picker.complete(GoogleAuthProvider.credential(idToken: 'emulated-token'));
    await rejected;
    expect(original.credentials, isEmpty);
    expect((auth.currentUser as TestUser).credentials, isEmpty);
  });
  test('a second operation is blocked while Google is open', () async {
    final user = TestUser('guest');
    final picker = Completer<AuthCredential?>();
    final service =
        AccountService(auth: TestAuth(user), googlePicker: () => picker.future);
    final first = service.linkGoogle();
    await expectLater(
        service.linkEmail('other@example.test', 'safe-password'),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'account-operation-in-progress')));
    picker.complete(null);
    await first;
    expect(user.credentials, isEmpty);
  });
  test('email recovery cannot replace an active guest', () async {
    final auth = TestAuth(TestUser('guest'));
    await expectLater(
        AccountService(auth: auth).signInEmail('old@example.test', 'password'),
        throwsA(isA<FirebaseAuthException>()));
    expect(auth.currentUser!.uid, 'guest');
    expect(auth.logins, 0);
  });
  test('email recovery works from a signed-out session', () async {
    final auth = TestAuth(null);
    await AccountService(auth: auth)
        .signInEmail('old@example.test', 'password');
    expect(auth.currentUser!.uid, 'restored');
    expect(auth.logins, 1);
  });
}
