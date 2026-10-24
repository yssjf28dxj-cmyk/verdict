import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/widgets/push_settings_card.dart';

Widget app(Widget child,
        {String language = 'ru', double scale = 1}) =>
    MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(body: SingleChildScrollView(child: child)));
void main() {
  testWidgets(
      'viewing settings does not request opt-in and pending changes cannot duplicate',
      (tester) async {
    var writes = 0;
    final result = Completer<void>();
    await tester.pumpWidget(app(PushSettingsCard(
        read: () async => false,
        write: (enabled) {
          writes++;
          expect(enabled, true);
          return result.future;
        })));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(writes, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    result.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
  });
  testWidgets(
      'denied permission or network error does not fabricate enabled state',
      (tester) async {
    await tester.pumpWidget(app(PushSettingsCard(
        read: () async => false,
        write: (_) async {
          throw StateError('Denied');
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    expect(
        find.text(
            'Не удалось настроить уведомления. Проверьте соединение и разрешение в настройках устройства.'),
        findsOneWidget);
  });
  testWidgets(
      'failed initial read is retriable and never shown as an opted-out account',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(app(PushSettingsCard(
        read: () async {
          reads++;
          if (reads == 1) throw StateError('offline');
          return true;
        },
        write: (_) async {})));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.widgetWithText(
        TextButton,
        AppLocalizations.of(tester.element(find.byType(PushSettingsCard)))!
            .retryMediaLabel));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
  });
  for (final language in ['ru', 'en', 'ar', 'fr', 'es', 'hi', 'zh']) {
    testWidgets(
        'notification settings fit a narrow $language screen with large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(
          PushSettingsCard(read: () async => true, write: (_) async {}),
          language: language,
          scale: 1.6));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
