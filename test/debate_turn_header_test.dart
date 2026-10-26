import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/utils/arena_theme.dart';
import 'package:verdict/widgets/debate_turn_header.dart';

Widget host(Widget child, {Locale locale = const Locale('ru')}) => MaterialApp(
      key: ValueKey(locale.languageCode),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ArenaTheme.from(ThemeData.dark(useMaterial3: true)),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
DebateTurnHeader header(
        {bool compact = false,
        VoidCallback? handoff,
        VoidCallback? accept,
        bool active = true,
        bool accepting = false,
        int seconds = 125}) =>
    DebateTurnHeader(
      fighter1: 'Первый участник с длинным именем',
      fighter2: 'Second participant with a long name',
      statusLabel: 'Ваш ход',
      remainingSeconds: seconds,
      active: active,
      round: 2,
      totalRounds: 3,
      votes1: 0,
      votes2: 0,
      viewers: 12345,
      compact: compact,
      bank1Seconds: 35,
      bank2Seconds: 65,
      activeSide: 1,
      onHandoff: handoff,
      onAccept: accept,
      accepting: accepting,
    );
void main() {
  testWidgets(
      'one turn clock, names and banks fit seven languages with 200% text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(host(header(handoff: () {}), locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: locale.languageCode);
      expect(find.byKey(const ValueKey('active-turn-clock')), findsOneWidget);
      expect(find.text('02:05'), findsOneWidget);
      expect(find.textContaining('+00:35'), findsOneWidget);
      expect(find.textContaining('+01:05'), findsOneWidget);
      final button = find.byType(TextButton);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
  });
  testWidgets(
      'compact header retains the sole clock and status without bank controls',
      (tester) async {
    await tester.pumpWidget(host(header(compact: true, handoff: () {})));
    await tester.pumpAndSettle();
    expect(find.text('02:05'), findsOneWidget);
    expect(find.text('Ваш ход'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('+00:35'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'handoff calls the existing action once and unavailable handoff stays absent',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(header(handoff: () => calls++)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton));
    expect(calls, 1);
    await tester.pumpWidget(host(header()));
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);
  });
  testWidgets(
      'waiting and accepting states never display a running clock or duplicate acceptance',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(header(active: false, accept: () => calls++)));
    await tester.pumpAndSettle();
    expect(find.text('--:--'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(calls, 1);
    await tester.pumpWidget(
        host(header(active: false, accept: () => calls++, accepting: true)));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
  test('clock clamps expired time without inventing a new turn', () {
    expect(DebateTurnHeader.clock(-3), '00:00');
    expect(DebateTurnHeader.clock(600), '10:00');
  });
}
