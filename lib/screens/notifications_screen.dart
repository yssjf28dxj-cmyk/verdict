import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../firebase_session.dart';
import '../firestore_database.dart';
import '../l10n/app_localizations.dart';
import '../utils/push_destination.dart';

String pushEventLabel(AppLocalizations l10n, String kind) => switch (kind) {
      'accepted' => l10n.pushAccepted,
      'turn' => l10n.pushTurn,
      'finished' => l10n.pushFinished,
      _ => l10n.pushTitle,
    };

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.events, this.currentUid});
  final Stream<QuerySnapshot<Map<String, dynamic>>>? events;
  final String? Function()? currentUid;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? get _currentUid => widget.currentUid != null
      ? widget.currentUid!()
      : appAuth.currentUser?.uid;
  late final String? _uid = _currentUid;
  Timer? _initialTimeout;
  bool _timedOut = false;
  bool _received = false;
  @override
  void initState() {
    super.initState();
    _initialTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted && !_received) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _initialTimeout?.cancel();
    super.dispose();
  }

  int _attempt = 0;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _newEvents() =>
      widget.events ??
      (_uid == null
          ? null
          : appFirestore
              .collection('users')
              .doc(_uid)
              .collection('notifications')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .snapshots());
  late Stream<QuerySnapshot<Map<String, dynamic>>>? _events = _newEvents();
  void _retry() {
    _initialTimeout?.cancel();
    setState(() {
      _attempt++;
      _received = false;
      _timedOut = false;
      _events = _newEvents();
    });
    _initialTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted && !_received) setState(() => _timedOut = true);
    });
  }

  Future<void> _open(QueryDocumentSnapshot<Map<String, dynamic>> row) async {
    final data = row.data(), expiry = row.data()['expiresAt'];
    final target = PushDestination.parse({
      ...data,
      'notificationId': row.id,
      'expiresAtMs': expiry is Timestamp ? expiry.millisecondsSinceEpoch : 0
    }, _currentUid, DateTime.now().millisecondsSinceEpoch);
    if (target == null) return;
    // Opening is authorized anew by LobbyScreen; a failed read marker does not
    // stop the user from opening an otherwise available battle.
    try {
      await row.reference
          .update({'read': true}).timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (mounted) openPushDestination(GoRouter.of(context), target, _currentUid);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
        appBar: AppBar(title: Text(l10n.pushInbox), actions: [
          IconButton(
              tooltip: l10n.refreshDebates,
              onPressed: _retry,
              icon: const Icon(Icons.refresh))
        ]),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey(_attempt),
            stream: _events,
            builder: (context, snapshot) {
              if (snapshot.hasData || snapshot.hasError) {
                _received = true;
                _initialTimeout?.cancel();
              }
              if (_timedOut && !snapshot.hasData) {
                return Center(child: Text(l10n.pushError));
              }
              if (_uid == null || _currentUid != _uid || snapshot.hasError) {
                return Center(child: Text(l10n.pushError));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!.docs;
              if (rows.isEmpty) return Center(child: Text(l10n.pushEmpty));
              return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index],
                        data = row.data(),
                        expiry = data['expiresAt'];
                    final expired = expiry is! Timestamp ||
                        expiry.millisecondsSinceEpoch <=
                            DateTime.now().millisecondsSinceEpoch;
                    return ListTile(
                        leading: Icon(data['read'] == true
                            ? Icons.notifications_none
                            : Icons.notifications_active_outlined),
                        title: Text(pushEventLabel(l10n, '${data['kind']}')),
                        subtitle: expired ? Text(l10n.pushExpired) : null,
                        onTap: expired ? null : () => _open(row));
                  });
            }));
  }
}
