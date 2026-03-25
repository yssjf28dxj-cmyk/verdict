import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          Center(
            child: GlassCard(
              child: Text(
                l10n.welcomeHeadline,
                style: const TextStyle(
                  color: Colors.white,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
