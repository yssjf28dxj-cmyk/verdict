import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../firebase_session.dart';

typedef GoogleCredentialPicker = Future<AuthCredential?> Function();

// Enable only after registering the signing certificate, enabling the provider,
// and refreshing google-services.json with the test app's OAuth clients.
const googleSignInConfigured =
    bool.fromEnvironment('VERDICT_GOOGLE_SIGN_IN_ENABLED');

// Keep the existing production sign-in behavior; only the unconfigured test
// app's legacy login is gated here. New linking always requires the flag.
bool get googleLoginAvailable => !testProfilesEnabled || googleSignInConfigured;

/// Links credentials to the current guest. Never signs out, merges accounts,
/// or copies public profile data. Firebase retains the original UID and claims.
class AccountService {
  AccountService(
      {FirebaseAuth? auth,
      GoogleCredentialPicker? googlePicker,
      bool? googleEnabled})
      : auth = auth ?? appAuth,
        googleAvailable =
            googleEnabled ?? (googlePicker != null || googleSignInConfigured),
        _googlePicker = googlePicker ?? pickGoogleCredential;

  final FirebaseAuth auth;
  final bool googleAvailable;
  final GoogleCredentialPicker _googlePicker;
  bool _busy = false;

  static Future<AuthCredential?> pickGoogleCredential() async {
    final google = GoogleSignIn();
    // Ask for an account explicitly; signing out here affects only the provider
    // picker, never the guest's Firebase session.
    await google.signOut();
    final account = await google.signIn();
    if (account == null) return null;
    final token = await account.authentication;
    return GoogleAuthProvider.credential(
        accessToken: token.accessToken, idToken: token.idToken);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw FirebaseAuthException(code: 'account-operation-in-progress');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  User _guest() {
    final user = auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw FirebaseAuthException(code: 'guest-session-required');
    }
    return user;
  }

  void _sameGuest(User guest) {
    if (auth.currentUser?.uid != guest.uid ||
        auth.currentUser?.isAnonymous != true) {
      throw FirebaseAuthException(code: 'guest-session-changed');
    }
  }

  Future<UserCredential?> linkGoogle() => _exclusive(() async {
        if (!googleAvailable) {
          throw FirebaseAuthException(code: 'operation-not-allowed');
        }
        final guest = _guest();
        final credential = await _googlePicker();
        if (credential == null) return null;
        _sameGuest(guest);
        return guest.linkWithCredential(credential);
      });

  Future<UserCredential> linkEmail(String email, String password) =>
      _exclusive(() async {
        final guest = _guest();
        return guest.linkWithCredential(EmailAuthProvider.credential(
            email: email.trim(), password: password));
      });

  Future<UserCredential> signInEmail(String email, String password) =>
      _exclusive(() async {
        // Recovery is an explicit signed-out flow. Never replace an active guest.
        if (auth.currentUser != null) {
          throw FirebaseAuthException(code: 'guest-session-changed');
        }
        return auth.signInWithEmailAndPassword(
            email: email.trim(), password: password);
      });

  Future<void> resetPassword(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  Future<void> sendVerification() async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous || user.email == null) {
      throw FirebaseAuthException(code: 'guest-session-required');
    }
    await user.sendEmailVerification();
  }

  Future<void> refresh() async => auth.currentUser?.reload();
}
