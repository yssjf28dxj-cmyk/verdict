import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';

String accountError(AppLocalizations l10n, Object error) {
  final code = error is FirebaseAuthException ? error.code : '';
  switch (code) {
    case 'credential-already-in-use':
    case 'email-already-in-use':
    case 'account-exists-with-different-credential':
      return l10n.accountConflict;
    case 'guest-session-required':
    case 'guest-session-changed':
      return l10n.accountSessionChanged;
    case 'operation-not-allowed':
      return l10n.accountProviderDisabled;
    case 'invalid-email':
      return l10n.accountEmailInvalid;
    case 'weak-password':
      return l10n.accountPasswordHint;
    case 'invalid-credential':
    case 'invalid-login-credentials':
    case 'wrong-password':
    case 'user-not-found':
      return l10n.accountCredentialsInvalid;
    case 'network-request-failed':
      return l10n.accountNetworkError;
    default:
      // Never expose provider exception text, email addresses or native details.
      return l10n.accountActionFailed;
  }
}
