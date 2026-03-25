import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'auth_screen.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  Timer? _authTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();
    _authTimer = Timer(const Duration(seconds: 3), _checkAuth);
  }

  void _checkAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    if (user != null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const AuthScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
    }
  }

  @override
  void dispose() {
    _authTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Image.asset(
                'assets/logo.png',
                width: 160,
                height: 160,
                cacheWidth: 320,
                cacheHeight: 320,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
