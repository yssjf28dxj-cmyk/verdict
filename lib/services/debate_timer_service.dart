import 'package:verdict/firestore_database.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages the round countdown timer for a debate.
///
/// REFACTORED: No longer opens its own Firestore stream.
/// Instead, the caller feeds Firestore snapshots via [onDebateData].
/// This eliminates the duplicate stream that existed alongside
/// the one in DebateRoomScreen, saving Firestore read costs
/// and preventing desync on slow networks.
class DebateTimerService {
  final String debateId;
  final int initialSeconds;
  final VoidCallback onTimerEnd;
  final ValueNotifier<int> timeLeftNotifier;

  Timer? _ticker;
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

  /// Call this each time the parent stream emits new debate data.
  /// Replaces the internal Firestore subscription.
  void onDebateData(Map<String, dynamic> data) {
    final roundIndex = _readRoundIndex(data);
    if (roundIndex != _activeRoundIndex) {
      _activeRoundIndex = roundIndex;
      _didFireTimerEnd = false;
    }

    _isTimerRunning = data['isTimerRunning'] == true;
    if (_isTimerRunning) {
      _syncTimer(data);
    } else {
      _pauseTicker();
    }
  }

  /// Legacy entry point — still supported for callers that need
  /// the service to manage its own subscription (e.g. isolated widgets).
  StreamSubscription<DocumentSnapshot>? _debateSub;

  /// Opens its own stream — use only when you can't feed data externally.
  void startWithOwnStream() {
    _debateSub?.cancel();
    _ticker?.cancel();
    _debateSub = appFirestore
        .collection('debates')
        .doc(debateId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data == null) return;
      onDebateData(data);
    }, onError: (Object error) {
      debugPrint('DebateTimerService stream error: $error');
      _pauseTicker();
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
      final n = raw.toInt();
      return n > 0 ? n : initialSeconds;
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
    _ticker?.cancel();

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

    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
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

  void _pauseTicker() {
    _ticker?.cancel();
    _roundEndsAt = null;
    _didFireTimerEnd = false;
  }

  void dispose() {
    _ticker?.cancel();
    _debateSub?.cancel();
    _ticker = null;
    _debateSub = null;
  }
}
