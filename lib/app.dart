import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'screens/splash_screen.dart';
import 'services/app_locale_controller.dart';

class VerdictApp extends StatelessWidget {
  final ThemeData theme;
  final AppLocaleController localeController;

  const VerdictApp({
    super.key,
    required this.theme,
    required this.localeController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'VERDICT',
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: localeController.locale,
          supportedLocales: AppLocaleController.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const SplashScreen(),
        );
      },
    );
  }
}
