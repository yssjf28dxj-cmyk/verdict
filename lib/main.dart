import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'services/sound_service.dart';
import 'utils/style_utils.dart';
import 'services/app_locale_controller.dart';

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
  } catch (_) {
    // Keep default mode when API is unavailable.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Эмулятор отключён — все вызовы идут в продакшн.
  // if (kDebugMode) {
  //   FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
  // }
  await _enableHighRefreshRate();
  await AppLocaleController.instance.loadSavedLocale();
  await SoundService.instance.warmUp();
  runApp(
    VerdictApp(
      theme: buildVerdictTheme(),
      localeController: AppLocaleController.instance,
    ),
  );
}
