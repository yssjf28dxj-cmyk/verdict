import 'dart:ui';

import 'package:flutter/material.dart';

class VerdictStyle {
  static const Color bg = Color(0xFF0E1320);
  static const Color cardBg = Color(0xFF1D2233);
  static const Color accentGold = Color(0xFFFFA500);
  static const Color fighterBlue = Color(0xFF2196F3);
  static const Color fighterRed = Color(0xFFFF4B4B);

  static const BorderRadius radius24 = BorderRadius.all(Radius.circular(24));

  static const LinearGradient arenaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x330F3D78),
      Color(0x22FF4B4B),
    ],
  );

  static const TextStyle headingStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  static BoxDecoration glassDecoration({
    BorderRadius borderRadius = radius24,
  }) {
    return BoxDecoration(
      borderRadius: borderRadius,
      color: const Color(0xAA1D2233),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.05),
        width: 1,
      ),
      gradient: arenaGradient,
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool enableBlur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = VerdictStyle.radius24,
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: VerdictStyle.glassDecoration(borderRadius: borderRadius),
      child: child,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: RepaintBoundary(
        child: enableBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: content,
              )
            : content,
      ),
    );
  }
}

class LivePulseIndicator extends StatefulWidget {
  final String label;

  const LivePulseIndicator({
    super.key,
    this.label = 'LIVE',
  });

  @override
  State<LivePulseIndicator> createState() => _LivePulseIndicatorState();
}

class _LivePulseIndicatorState extends State<LivePulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_controller),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x29FF4B4B),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x99FF4B4B)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: VerdictStyle.fighterRed,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                color: Color(0xFFFFB3B3),
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
