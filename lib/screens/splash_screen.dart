import 'package:verdict/firebase_session.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';
import '../services/app_locale_controller.dart';
import '../services/sound_service.dart';
import '../utils/startup_route.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

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
    _initApp();
  }

  Future<void> _initApp() async {
    // В это время идет анимация SplashScreen, и мы загружаем тяжелые ресурсы:
    await Future.wait([
      AppLocaleController.instance.loadSavedLocale(),
      SoundService.instance.warmUp(),
      // Гарантируем, что сплеш висит минимум 1.2 секунды для завершения анимации
      Future.delayed(const Duration(milliseconds: 1200)),
    ]);
    _checkAuth();
  }

  void _checkAuth() {
    final user = appAuth.currentUser;
    if (!mounted || !mayCompleteStartup(GoRouter.of(context))) return;
    if (user != null) {
      if (context.mounted) context.go('/home');
    } else {
      if (context.mounted) context.go('/auth');
    }
  }

  @override
  void dispose() {
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
