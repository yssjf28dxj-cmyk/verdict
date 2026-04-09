import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'utils/router.dart';
import 'services/app_locale_controller.dart';
import 'widgets/pending_debate_banner.dart';

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
        return MaterialApp.router(
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
          routerConfig: appRouter,
          // PendingDebateBanner must be INSIDE MaterialApp so it
          // inherits Directionality, MediaQuery, and GoRouter context.
          builder: (context, child) => PendingDebateBanner(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
