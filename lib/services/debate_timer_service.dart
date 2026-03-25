import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DebateTimerService {
  final String debateId;
  final int initialSeconds;
  final VoidCallback onTimerEnd;
  final ValueNotifier<int> timeLeftNotifier;
  StreamSubscription<DocumentSnapshot>? _debateSub;
  Timer? _timer;
  bool _isTimerRunning = false;
  DateTime? _roundEndsAt;
  bool _didFireTimerEnd = false;
  int _activeRoundIndex = 1;

  DebateTimerService({
    required this.debateId,
    required this.initialSeconds,
    required this.onTimerEnd,
    required this.timeLeftNotifier,
  });

  void start() {
    _debateSub?.cancel();
    _timer?.cancel();
    _debateSub = FirebaseFirestore.instance
        .collection('debates')
        .doc(debateId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data == null) return;

      final roundIndex = _readRoundIndex(data);
      if (roundIndex != _activeRoundIndex) {
        _activeRoundIndex = roundIndex;
        _didFireTimerEnd = false;
      }

      _isTimerRunning = data['isTimerRunning'] ?? false;
      if (_isTimerRunning) {
        _syncTimer(data);
      } else {
        _stopTimer();
      }
    }, onError: (Object error) {
      debugPrint('DebateTimerService stream error: $error');
      _stopTimer();
      timeLeftNotifier.value = 0;
    });
  }

  int _readRoundIndex(Map<String, dynamic> data) {
    final raw = data['roundIndex'] ?? data['currentRound'] ?? data['round'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 1;
  }

  int _readDurationSeconds(Map<String, dynamic> data) {
    final raw = data['roundDurationSeconds'] ??
        data['durationSeconds'] ??
        data['durationSec'];
    if (raw is int) return raw > 0 ? raw : initialSeconds;
    if (raw is num) {
      final normalized = raw.toInt();
      return normalized > 0 ? normalized : initialSeconds;
    }
    return initialSeconds;
  }

  DateTime? _readRoundEnd(Map<String, dynamic> data) {
    final rawRoundEndsAt = data['roundEndsAt'];
    if (rawRoundEndsAt is Timestamp) return rawRoundEndsAt.toDate();

    final rawStart = data['startedAt'] ?? data['startTime'];
    DateTime? startedAt;
    if (rawStart is Timestamp) {
      startedAt = rawStart.toDate();
    } else if (rawStart is DateTime) {
      startedAt = rawStart;
    }
    if (startedAt == null) return null;

    final durationSeconds = _readDurationSeconds(data);
    return startedAt.add(Duration(seconds: durationSeconds));
  }

  int _remainingSeconds() {
    final end = _roundEndsAt;
    if (end == null) return 0;
    final diff = end.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  void _syncTimer(Map<String, dynamic> data) {
    _timer?.cancel();

    _roundEndsAt = _readRoundEnd(data);
    final fallbackSeconds = _readDurationSeconds(data);
    final initialLeft =
        _roundEndsAt != null ? _remainingSeconds() : fallbackSeconds;
    timeLeftNotifier.value = initialLeft;

    if (initialLeft <= 0) {
      if (!_didFireTimerEnd) {
        _didFireTimerEnd = true;
        onTimerEnd();
      }
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isTimerRunning) {
        t.cancel();
        return;
      }

      if (_roundEndsAt != null) {
        timeLeftNotifier.value = _remainingSeconds();
      } else if (timeLeftNotifier.value > 0) {
        timeLeftNotifier.value--;
      }

      if (timeLeftNotifier.value <= 0) {
        t.cancel();
        if (!_didFireTimerEnd) {
          _didFireTimerEnd = true;
          onTimerEnd();
        }
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _roundEndsAt = null;
    _didFireTimerEnd = false;
  }

  void dispose() {
    _stopTimer();
    _timer?.cancel();
    _debateSub?.cancel();
  }
}
