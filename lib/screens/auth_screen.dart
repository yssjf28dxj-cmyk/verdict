import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

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
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
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
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
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
              child: Padding(
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
                          onPressed: _isLoading ? null : _googleLogin,
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
