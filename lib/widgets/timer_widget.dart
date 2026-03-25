import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class DebateTimer extends StatefulWidget {
  final int startSeconds;

  const DebateTimer({super.key, required this.startSeconds});

  @override
  State<DebateTimer> createState() => _DebateTimerState();
}

class _DebateTimerState extends State<DebateTimer> {
  late int seconds;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    seconds = widget.startSeconds;

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seconds > 0) {
        setState(() {
          seconds--;
        });
      } else {
        timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(
      '${l10n.timeLabel}: $seconds',
      style: const TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
