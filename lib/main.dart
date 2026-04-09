import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'utils/style_utils.dart';
import 'services/app_locale_controller.dart';
import 'utils/di.dart';

ThemeData buildVerdictTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: VerdictStyle.accentGold,
    brightness: Brightness.dark,
  ).copyWith(
    primary: VerdictStyle.accentGold,
    secondary: VerdictStyle.accentGold,
    surface: VerdictStyle.bg,
    onSurface: Colors.white,
    onPrimary: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: VerdictStyle.bg,
    fontFamily: 'Roboto',
    cardTheme: CardThemeData(
      elevation: 0,
      color: VerdictStyle.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      titleLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      titleMedium: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
  );
}

Future<void> _enableHighRefreshRate() async {
  if (kIsWeb) return;
  try {
    final supported = await FlutterDisplayMode.supported;
    if (supported.isEmpty) return;
    final active = await FlutterDisplayMode.active;
    final sameResolution = supported
        .where(
          (m) => m.width == active.width && m.height == active.height,
        )
        .toList();
    final pool = sameResolution.isNotEmpty ? sameResolution : supported;
    pool.sort((a, b) => b.refreshRate.compareTo(a.refreshRate));
    await FlutterDisplayMode.setPreferredMode(pool.first);
  } catch (e, stackTrace) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(e, stackTrace, reason: 'High refresh rate fallback');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Firestore offline persistence ──────────────────────────────
  // On mobile: keeps all data cached locally when network drops.
  // On Web: relies on IndexedDB cache which is enabled by default.
  try {
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (_) {
    // Persistence already configured — safe to ignore
  }

  if (!kIsWeb) {
    // ── Mobile: send Flutter errors to Crashlytics ──────────────
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } else {
    // ── Web: log errors to console in debug, silent in release ──
    FlutterError.onError = (details) {
      if (kDebugMode) FlutterError.presentError(details);
    };
  }

  // ── Global widget error boundary ───────────────────────────────
  // Shows a branded error screen instead of the red crash overlay.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Re-report to crashlytics in release on mobile
    if (!kIsWeb && !kDebugMode) {
      FirebaseCrashlytics.instance.recordFlutterError(details);
    } else {
      debugPrint('[ErrorWidget] ${details.exceptionAsString()}');
    }
    return Material(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFFD700), size: 56),
              const SizedBox(height: 20),
              const Text(
                'Что-то пошло не так',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                kDebugMode ? details.exceptionAsString() : 'Перезапустите приложение',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  };

  await _enableHighRefreshRate();
  setupDI();

  runApp(
    VerdictApp(
      theme: buildVerdictTheme(),
      localeController: AppLocaleController.instance,
    ),
  );
}
