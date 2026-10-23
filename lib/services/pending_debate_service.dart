import 'package:verdict/firestore_database.dart';
import 'dart:async';
import 'package:flutter/material.dart';

/// Service that monitors a pending debate in the background.
/// When the debate status changes to 'active', it notifies listeners
/// so the UI can show a banner and navigate to the debate room.
typedef PendingDebateUpdates = Stream<Map<String, dynamic>?> Function(String);

class PendingDebateService extends ChangeNotifier {
  PendingDebateService._()
      : _updates = ((id) => appFirestore
            .collection('debates')
            .doc(id)
            .snapshots()
            .map((snapshot) => snapshot.data()));
  PendingDebateService.forTesting(this._updates);
  static final PendingDebateService instance = PendingDebateService._();
  final PendingDebateUpdates _updates;

  String? _watchedDebateId;
  String? _watchedTopic;
  StreamSubscription<Map<String, dynamic>?>? _sub;

  bool _activated = false;
  int _generation = 0;

  /// The debate ID that just became active (non-null = show banner).
  String? get activatedDebateId => _activated ? _watchedDebateId : null;
  String? get activatedTopic => _activated ? _watchedTopic : null;

  /// Whether we are currently watching a pending debate.
  bool get isWatching => _watchedDebateId != null && !_activated;

  String? get watchedDebateId => _watchedDebateId;

  /// Start watching [debateId] for status changes.
  void startWatching(String debateId, {String topic = ''}) {
    // Already watching this same debate — no-op.
    if (_watchedDebateId == debateId && !_activated) return;
    _stopInternal();
    final generation = _generation;

    _watchedDebateId = debateId;
    _watchedTopic = topic;
    _activated = false;

    _sub = _updates(debateId).listen((data) {
      if (generation != _generation) return;
      if (data == null) {
        if (_watchedDebateId == debateId) stopWatching();
        return;
      }
      final status = (data['status'] ?? '').toString();
      if ((status == 'active' || status == 'live') && !_activated) {
        _activated = true;
        notifyListeners();
      }
      // If debate is cancelled/deleted while watching.
      if (status == 'cancelled' || status == 'deleted') {
        stopWatching();
      }
    }, onError: (Object error) {
      // Revoked/private access is a normal outcome when following a locator.
      // Do not leak an unhandled permission error or clear a newer watcher.
      if (generation == _generation && _watchedDebateId == debateId) {
        stopWatching();
      }
    });

    notifyListeners();
  }

  /// Update the topic text shown in the banner (called when stream delivers data).
  void updateTopic(String debateId, String topic) {
    if (_watchedDebateId != debateId) return;
    if (_watchedTopic == topic) return;
    _watchedTopic = topic;
    notifyListeners();
  }

  /// Call after navigating to the debate room.
  void stopWatching() {
    _stopInternal();
    _activated = false;
    _watchedDebateId = null;
    _watchedTopic = null;
    notifyListeners();
  }

  void _stopInternal() {
    _generation++;
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _stopInternal();
    super.dispose();
  }
}
