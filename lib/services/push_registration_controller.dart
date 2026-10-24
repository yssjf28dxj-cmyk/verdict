/// Serializes token registration, account switching and preference changes.
/// Native permission prompts happen only in enable(), never during sync().
class PushRegistrationController {
  PushRegistrationController(
      {required this.currentUid,
      required this.installationKey,
      required this.readEnabled,
      required this.configure,
      required this.register,
      required this.unregister,
      required this.hasPermission,
      required this.requestPermission,
      required this.setAutoInit,
      required this.getToken,
      required this.deleteToken,
      required this.readBinding,
      required this.writeBinding});
  final String? Function() currentUid;
  final Future<String> Function() installationKey;
  final Future<bool> Function(String) readEnabled;
  final Future<void> Function(String, bool) configure;
  final Future<void> Function(String, String, String) register;
  final Future<void> Function(String, String) unregister;
  final Future<bool> Function() hasPermission, requestPermission, readBinding;
  final Future<void> Function(bool) setAutoInit, writeBinding;
  final Future<String?> Function() getToken;
  final Future<void> Function() deleteToken;
  Future<void> _tail = Future.value();
  String? _boundToken, _boundUid;
  Future<void> _serial(Future<void> Function() work) {
    final next = _tail.then((_) => work());
    _tail =
        next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }

  void _check(String uid) {
    if (currentUid() != uid) throw StateError('Session changed');
  }

  Future<void> _retire() async {
    await setAutoInit(false);
    if (!await readBinding()) {
      _boundToken = null;
      _boundUid = null;
      return;
    }
    final uid = currentUid();
    if (uid == null) {
      await deleteToken();
    } else {
      await unregister(uid, await installationKey());
    }
    await writeBinding(false);
    _boundToken = null;
    _boundUid = null;
  }

  Future<void> retire() => _serial(_retire);
  Future<void> sync({String? refreshedToken}) => _serial(() async {
        if (refreshedToken != null &&
            _boundToken == refreshedToken &&
            _boundUid == currentUid()) {
          return;
        }
        final current = currentUid();
        if (current != null &&
            _boundUid == current &&
            _boundToken != null &&
            refreshedToken == null) {
          final enabled = await readEnabled(current);
          _check(current);
          final allowed = await hasPermission();
          _check(current);
          if (enabled && allowed) return;
          await _retire();
          return;
        }
        await _retire();
        final uid = currentUid();
        if (uid == null) return;
        final enabled = await readEnabled(uid);
        _check(uid);
        if (!enabled || !await hasPermission()) return;
        _check(uid);
        await _bind(uid);
      });
  Future<void> _bind(String uid) async {
    await setAutoInit(true);
    _check(uid);
    final token = await getToken();
    _check(uid);
    if (token == null) throw StateError('Push token unavailable');
    final key = await installationKey();
    _check(uid);
    // Persist before the request: a lost acknowledgement may still have bound
    // the device, so the next logout must attempt to retire it.
    await writeBinding(true);
    _check(uid);
    await register(uid, token, key);
    _check(uid);
    _boundToken = token;
    _boundUid = uid;
  }

  Future<void> enable() => _serial(() async {
        final uid = currentUid();
        if (uid == null) throw StateError('Authentication required');
        if (!await requestPermission()) {
          throw StateError('Notification permission denied');
        }
        _check(uid);
        final previous = await readEnabled(uid);
        _check(uid);
        await configure(uid, true);
        _check(uid);
        try {
          await _retire();
          _check(uid);
          await _bind(uid);
        } catch (_) {
          if (currentUid() == uid && !previous) await configure(uid, false);
          rethrow;
        }
      });
  Future<void> disable() => _serial(() async {
        final uid = currentUid();
        if (uid == null) throw StateError('Authentication required');
        await configure(uid, false);
        _check(uid);
        await _retire();
      });
}
