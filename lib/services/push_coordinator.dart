import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_session.dart';
import '../firestore_database.dart';
import '../utils/push_destination.dart';
import 'app_locale_controller.dart';
import 'push_registration_controller.dart';

final pushCoordinator = PushCoordinator();

class PushCoordinator with WidgetsBindingObserver {
  PushRegistrationController? _controller;
  StreamSubscription<User?>? _auth;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _opened, _foreground;
  Timer? _refreshTimer;
  bool _started = false;
  String? _token;
  void Function(PushDestination)? onOpen, onForeground;
  bool get available =>
      testProfilesEnabled && !kIsWeb && Firebase.apps.isNotEmpty;
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();
  void _check(String uid) {
    if (appAuth.currentUser?.uid != uid) throw StateError('Session changed');
  }

  Future<int> _nextGeneration() async {
    final prefs = await _prefs;
    final value = (prefs.getInt('verdict.push.generation') ?? 0) + 1;
    if (!await prefs.setInt('verdict.push.generation', value)) {
      throw StateError('Cannot preserve installation generation');
    }
    return value;
  }

  Future<String> _key() async {
    final prefs = await _prefs;
    var key = prefs.getString('verdict.push.installation');
    if (key == null) {
      final random = Random.secure();
      key = List.generate(
              32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      if (!await prefs.setString('verdict.push.installation', key)) {
        throw StateError('Cannot preserve installation identity');
      }
    }
    return key;
  }

  Future<void> _call(String uid, String name, Map<String, dynamic> data) async {
    _check(uid);
    final functions = appFunctions;
    final callable = functions.httpsCallable(name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
    var payload = data;
    for (var attempt = 0; attempt < 3; attempt++) {
      _check(uid);
      try {
        await callable.call(payload);
        _check(uid);
        return;
      } on FirebaseFunctionsException catch (error) {
        if (attempt == 2) rethrow;
        final details = error.details;
        final next = details is Map ? details['nextGeneration'] : null;
        if (['registerPushDevice', 'unregisterPushDevice'].contains(name) &&
            error.code == 'aborted' &&
            next is int &&
            next > 0 &&
            next < 9007199254740991) {
          _check(uid);
          final prefs = await _prefs;
          final generation =
              max(next, (prefs.getInt('verdict.push.generation') ?? 0) + 1);
          if (!await prefs.setInt('verdict.push.generation', generation)) {
            throw StateError('Cannot repair installation generation');
          }
          payload = {...payload, 'generation': generation};
        } else if (name == 'registerPushDevice' &&
            error.code == 'resource-exhausted' &&
            details is Map &&
            details['retryAfterMs'] is num) {
          final delay = (details['retryAfterMs'] as num).ceil().clamp(1, 2000);
          await Future<void>.delayed(Duration(milliseconds: delay));
        } else {
          rethrow;
        }
      }
    }
  }

  Future<bool> enabled() async {
    final uid = appAuth.currentUser?.uid;
    if (uid == null) return false;
    final snapshot = await appFirestore
        .doc('users/$uid/private_settings/notifications')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    _check(uid);
    return snapshot.data()?['enabled'] == true;
  }

  PushRegistrationController get _registration =>
      _controller ??= PushRegistrationController(
        currentUid: () => appAuth.currentUser?.uid,
        installationKey: _key,
        readEnabled: (uid) async {
          _check(uid);
          return enabled();
        },
        configure: (uid, enabled) =>
            _call(uid, 'configurePushNotifications', {'enabled': enabled}),
        register: (uid, token, key) async {
          final locale = AppLocaleController.instance.locale.languageCode;
          await _call(uid, 'registerPushDevice', {
            'token': token,
            'installationKey': key,
            'generation': await _nextGeneration(),
            'platform':
                defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
            'locale':
                ['ru', 'en', 'ar', 'fr', 'es', 'hi', 'zh'].contains(locale)
                    ? locale
                    : 'en'
          });
          _token = token;
        },
        unregister: (uid, key) async => _call(uid, 'unregisterPushDevice',
            {'installationKey': key, 'generation': await _nextGeneration()}),
        hasPermission: () async => _allowed(
            (await FirebaseMessaging.instance.getNotificationSettings())
                .authorizationStatus),
        requestPermission: () async => _allowed(
            (await FirebaseMessaging.instance.requestPermission())
                .authorizationStatus),
        setAutoInit: (value) =>
            FirebaseMessaging.instance.setAutoInitEnabled(value),
        getToken: () => FirebaseMessaging.instance.getToken(),
        deleteToken: () => FirebaseMessaging.instance.deleteToken(),
        readBinding: () async =>
            (await _prefs).getBool('verdict.push.bound') ?? false,
        writeBinding: (value) async {
          if (!await (await _prefs).setBool('verdict.push.bound', value)) {
            throw StateError('Cannot preserve binding state');
          }
        },
      );
  bool _allowed(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;
  Future<void> setEnabled(bool value) async {
    if (!available) throw StateError('Push unavailable');
    if (value) {
      await _registration.enable();
    } else {
      await _registration.disable();
    }
  }

  Future<void> beforeSessionChange() async {
    if (available) await _registration.retire();
  }

  void _sync() {
    if (available) {
      unawaited(_registration.sync().catchError((Object error) {
        debugPrint('Push registration could not be refreshed');
      }));
    }
  }

  void _attachAuth() {
    if (testProfiles.busy) return;
    _auth?.cancel();
    _auth = appAuth.authStateChanges().listen((_) => _sync());
  }

  Future<void> _receive(RemoteMessage message, {required bool opened}) async {
    final uid = (await appAuth.authStateChanges().first).uidOrNull;
    final target = PushDestination.parse(
        message.data, uid, DateTime.now().millisecondsSinceEpoch);
    if (target == null) return;
    final prefs = await _prefs;
    final storageKey = opened ? 'verdict.push.opened' : 'verdict.push.seen';
    final seen = prefs.getStringList(storageKey) ?? [];
    if (seen.contains(target.id)) return;
    _check(target.uid);
    if (!await prefs.setStringList(storageKey,
        [...seen, target.id].reversed.take(100).toList().reversed.toList())) {
      return;
    }
    if (opened) {
      onOpen?.call(target);
    } else {
      onForeground?.call(target);
    }
  }

  void start() {
    if (!available || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _attachAuth();
    testProfiles.addListener(_attachAuth);
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (token == _token) return;
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(seconds: 2), () {
        if (token != _token) {
          unawaited(_registration
              .sync(refreshedToken: token)
              .catchError((Object error) {
            debugPrint('Push token refresh deferred');
          }));
        }
      });
    });
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_receive(message, opened: true).catchError((Object error) {}));
    });
    _foreground = FirebaseMessaging.onMessage.listen((message) {
      unawaited(_receive(message, opened: false).catchError((Object error) {}));
    });
    unawaited(
        FirebaseMessaging.instance.getInitialMessage().then((message) async {
      if (message != null) await _receive(message, opened: true);
    }).catchError((Object error) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_started && state == AppLifecycleState.resumed) _sync();
  }

  void dispose() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    _refresh?.cancel();
    _opened?.cancel();
    _foreground?.cancel();
    _refreshTimer?.cancel();
    testProfiles.removeListener(_attachAuth);
    _started = false;
    onOpen = null;
    onForeground = null;
  }
}

extension on User? {
  String? get uidOrNull => this?.uid;
}
