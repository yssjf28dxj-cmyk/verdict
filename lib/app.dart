import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'utils/router.dart';
import 'services/app_locale_controller.dart';
import 'widgets/pending_debate_banner.dart';
import 'services/push_coordinator.dart';
import 'screens/notifications_screen.dart';
import 'firebase_session.dart';
import 'utils/push_destination.dart';

class VerdictApp extends StatefulWidget {
  final ThemeData theme;
  final AppLocaleController localeController;

  const VerdictApp({
    super.key,
    required this.theme,
    required this.localeController,
  });

  @override
  State<VerdictApp> createState() => _VerdictAppState();
}

class _VerdictAppState extends State<VerdictApp> {
  late final GoRouter _router = createAppRouter();

  @override
  void initState() {
    super.initState();
    pushCoordinator.onOpen = (target) {
      if (mounted) openPushDestination(_router, target, appAuth.currentUser?.uid);
    };
    pushCoordinator.onForeground = (target) {
      final context = _router.routerDelegate.navigatorKey.currentContext;
      if (!mounted || context == null || appAuth.currentUser?.uid != target.uid) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(pushEventLabel(l10n, target.kind)), duration: const Duration(seconds: 4),
        action: SnackBarAction(label: l10n.pushOpen, onPressed: () {
          openPushDestination(_router, target, appAuth.currentUser?.uid);
        })));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) pushCoordinator.start(); });
  }

  @override
  void dispose() {
    pushCoordinator.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.localeController,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'VERDICT',
          debugShowCheckedModeBanner: false,
          theme: widget.theme,
          locale: widget.localeController.locale,
          supportedLocales: AppLocaleController.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          routerConfig: _router,
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
