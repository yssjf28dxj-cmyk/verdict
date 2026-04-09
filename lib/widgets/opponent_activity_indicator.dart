import 'package:flutter/material.dart';

/// Displays a sleek animated indicator when the opponent is typing,
/// recording audio, or sending photos in the debate room.
///
/// Usage: Pass the raw `activity` string from Firestore ('typing',
/// 'recording', 'image'). An empty string hides the indicator.
class OpponentActivityIndicator extends StatefulWidget {
  final String activity;

  const OpponentActivityIndicator({
    super.key,
    required this.activity,
  });

  @override
  State<OpponentActivityIndicator> createState() =>
      _OpponentActivityIndicatorState();
}

class _OpponentActivityIndicatorState extends State<OpponentActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (widget.activity) {
      'typing' => ('Оппонент печатает', Icons.edit_rounded),
      'recording' => ('Оппонент записывает аудио', Icons.mic_rounded),
      'image' => ('Оппонент отправляет фото', Icons.photo_camera_rounded),
      _ => ('', Icons.more_horiz),
    };

    if (label.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _dotCtrl,
      builder: (_, __) {
        // Three dots that appear sequentially
        final dotCount = (_dotCtrl.value * 4).floor().clamp(0, 3);
        final dots = '.' * dotCount;
        final padDots = '   '.substring(0, 3 - dotCount);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: const Color(0xFFFFA500).withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              '$label$dots$padDots',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55),
                letterSpacing: 0.2,
              ),
            ),
          ],
        );
      },
    );
  }
}
