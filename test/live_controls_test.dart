import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/widgets/debate_setup_controls.dart';
import 'package:verdict/widgets/pending_media_bubble.dart';
import 'package:verdict/utils/compact_notice.dart';

Widget host(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(body: child));
void main() {
  testWidgets(
      'setup controls fit supported languages with enlarged text on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: DebateSetupControls(
                              duration: 180,
                              rounds: 3,
                              visibility: 'public',
                              directInvite: false,
                              onDuration: (_) {},
                              onRounds: (_) {},
                              onVisibility: (_) {},
                              onDirectInvite: (_) {})))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Overflow in ${locale.languageCode}');
    }
  });
  testWidgets(
      'duration, rounds and invite controls remain usable on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int duration = 180, rounds = 3;
    bool direct = false;
    String visibility = 'public';
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, update) => Padding(
            padding: const EdgeInsets.all(12),
            child: DebateSetupControls(
                duration: duration,
                rounds: rounds,
                visibility: visibility,
                directInvite: direct,
                onDuration: (v) => update(() => duration = v),
                onRounds: (v) => update(() => rounds = v),
                onDirectInvite: (v) => update(() => direct = v),
                onVisibility: (v) => update(() => visibility = v))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('direct-invite')));
    await tester.pumpAndSettle();
    expect(direct, isTrue);
    await tester.drag(find.byType(Slider), const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(DebateSetupControls.durations.contains(duration), isTrue);
    expect(duration, isNot(180));
    await tester.tap(find.text('5 раундов'));
    await tester.pumpAndSettle();
    expect(rounds, 5);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'setup options expose selection and stay disabled while publishing',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(SingleChildScrollView(
        child: DebateSetupControls(
            duration: 180,
            rounds: 3,
            visibility: 'public',
            directInvite: false,
            enabled: false,
            onDuration: (_) => calls++,
            onRounds: (_) => calls++,
            onVisibility: (_) => calls++,
            onDirectInvite: (_) => calls++))));
    final selected =
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('rounds-3')));
    expect(selected.selected, isTrue);
    expect(selected.onSelected, isNull);
    expect(tester.getSize(find.byKey(const ValueKey('rounds-3'))).height,
        greaterThanOrEqualTo(48));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    for (final name in ['public', 'request_only', 'private']) {
      final option = find.byKey(ValueKey('visibility-$name'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      expect(tester.widget<ChoiceChip>(option).onSelected, isNull);
    }
    expect(calls, 0);
  });
  testWidgets(
      'pending media stays a compact unconfirmed bubble and exposes retry after failure',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(host(PendingMediaBubble(
        mediaType: 'voice', failed: true, onRetry: () => retries++)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('pending-media'))).height,
        lessThan(200));
    await tester.tap(find.byIcon(Icons.refresh));
    expect(retries, 1);
  });
  testWidgets('compact notice disappears without blocking the composer',
      (tester) async {
    await tester.pumpWidget(host(Builder(
        builder: (context) => TextButton(
            onPressed: () => showCompactNotice(context, 'Попробуйте ещё раз'),
            child: const Text('show')))));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.behavior, SnackBarBehavior.floating);
    expect(snack.width, lessThanOrEqualTo(360));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Попробуйте ещё раз'), findsNothing);
  });
}
