import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/widgets/save_debate_button.dart';

Widget app(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child));
void main() {
  testWidgets(
      'saved state changes only after acknowledgement and pending writes cannot duplicate',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(app(SaveDebateButton(
        debateId: 'battle',
        read: (_) async => false,
        write: (_, saved) {
          calls++;
          expect(saved, true);
          return pending.future;
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить дебат'));
    await tester.pump();
    expect(calls, 1);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Убрать из избранного'), findsOneWidget);
  });
  testWidgets('failed write keeps the old state and allows retry',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(SaveDebateButton(
        debateId: 'battle',
        read: (_) async => true,
        write: (_, saved) async {
          calls++;
          expect(saved, false);
          if (calls == 1) throw StateError('offline');
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Убрать из избранного'));
    await tester.pumpAndSettle();
    expect(find.text('Убрать из избранного'), findsOneWidget);
    await tester.tap(find.text('Убрать из избранного'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Сохранить дебат'), findsOneWidget);
  });
  testWidgets(
      'failed initial read never guesses unsaved state or writes on retry',
      (tester) async {
    var reads = 0, writes = 0;
    await tester.pumpWidget(app(SaveDebateButton(
        debateId: 'battle',
        read: (_) async {
          reads++;
          if (reads == 1) throw StateError('offline');
          return true;
        },
        write: (id, saved) async {
          writes++;
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(writes, 0);
    expect(find.text('Убрать из избранного'), findsOneWidget);
  });
}
