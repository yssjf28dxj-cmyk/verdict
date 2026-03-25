import 'package:flutter/material.dart';

class ChatPatternPainter extends CustomPainter {
  final Color color;

  const ChatPatternPainter({
    this.color = const Color(0x0F000000),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Лёгкий, ненавязчивый паттерн "мессенджера".
    // Дешево по рендеру: простые круги по сетке.
    const double step = 56;
    const double r = 10;

    for (double y = -step; y < size.height + step; y += step) {
      for (double x = -step; x < size.width + step; x += step) {
        final dx = ((y / step).round().isEven) ? 0.0 : step / 2;
        canvas.drawCircle(Offset(x + dx, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChatPatternPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

