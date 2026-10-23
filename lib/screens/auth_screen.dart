import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:go_router/go_router.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import '../services/account_service.dart';
import '../widgets/email_account_dialog.dart';
import '../utils/invitation_links.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.returnTo});
  final String? returnTo;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String get _afterLogin => invitationReturnPath(widget.returnTo) ?? '/';

  Future<void> _emailLogin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final signedIn = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              EmailAccountDialog(service: AccountService(), linking: false));
      if (!mounted) return;
      if (signedIn == true) context.go(_afterLogin);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() {
      _isLoading = true;
    });

    final result = await _authService.signInAnonymously();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result != null) {
      context.go(_afterLogin);
    } else {
      final l10n = AppLocalizations.of(context)!;
      final reason = _authService.lastErrorCode;
      final suffix =
          (reason == null || reason.isEmpty) ? '' : ' (code: $reason)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.guestSignInFailed}$suffix')),
      );
    }
  }

  Future<void> _googleLogin() async {
    setState(() {
      _isLoading = true;
    });

    final result = await _authService.signInWithGoogle();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result != null) {
      context.go(_afterLogin);
    } else {
      final l10n = AppLocalizations.of(context)!;
      final reason = _authService.lastErrorCode;
      final suffix =
          (reason == null || reason.isEmpty) ? '' : ' (code: $reason)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.googleSignInUnavailable}$suffix')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.gavel,
                        size: 70,
                        color: VerdictStyle.accentGold,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'VERDICT',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading || !googleLoginAvailable
                              ? null
                              : _googleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x662A3147),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: Text(l10n.signInWithGoogle),
                        ),
                      ),
                      if (!googleLoginAvailable)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(l10n.accountGoogleUnavailable,
                                textAlign: TextAlign.center)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _continueAsGuest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: VerdictStyle.accentGold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.black,
                                )
                              : Text(l10n.browseWithoutRegistration),
                        ),
                      ),
                      TextButton(
                          onPressed: _isLoading ? null : _emailLogin,
                          child: Text(l10n.accountEmailSignIn)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
