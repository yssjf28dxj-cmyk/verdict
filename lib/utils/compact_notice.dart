import 'dart:math' as math;
import 'package:flutter/material.dart';

void showCompactNotice(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    width: math.min(360, MediaQuery.sizeOf(context).width - 24),
    duration: const Duration(seconds: 2),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    backgroundColor: const Color(0xFF29303D),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    content: Text(message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: Colors.white)),
  ));
}
