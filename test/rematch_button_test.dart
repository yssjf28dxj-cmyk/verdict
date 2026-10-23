import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/widgets/rematch_button.dart';

GoRouter router(RequestRematch request) => GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, state) => Scaffold(
              body: RematchButton(
                  sourceId: 'original',
                  topic: 'Test topic',
                  opponentName: 'Opponent',
                  durationSeconds: 60,
                  rounds: 3,
                  request: request))),
      GoRoute(
          path: '/lobby/:id',
          builder: (_, state) =>
              Scaffold(body: Text('waiting:${state.pathParameters['id']}'))),
    ]);
Widget app(GoRouter router) => MaterialApp.router(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router);

Future<void> confirm(WidgetTester tester) async {
  await tester.tap(find.text('Предложить реванш'));
  await tester.pumpAndSettle();
  expect(find.textContaining('новый приватный вызов'), findsOneWidget);
  expect(find.textContaining('1:00'), findsOneWidget);
  await tester.tap(find.text('Отправить вызов'));
}

void main() {
  testWidgets('cancelling the terms dialog does not create a challenge',
      (tester) async {
    var calls = 0;
    final routes = router((source, id) async {
      calls++;
      return 'new';
    });
    addTearDown(routes.dispose);
    await tester.pumpWidget(app(routes));
    await tester.tap(find.text('Предложить реванш'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextButton)));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
  testWidgets('confirmed terms send one request and open the new waiting room',
      (tester) async {
    var calls = 0;
    final result = Completer<String>();
    final routes = router((source, id) {
      calls++;
      expect(source, 'original');
      return result.future;
    });
    addTearDown(routes.dispose);
    await tester.pumpWidget(app(routes));
    await confirm(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    result.complete('new-rematch');
    await tester.pumpAndSettle();
    expect(find.text('waiting:new-rematch'), findsOneWidget);
  });
  testWidgets('lost response preserves request identity for a manual retry',
      (tester) async {
    final ids = <String>[];
    final routes = router((source, id) async {
      ids.add(id);
      if (ids.length == 1) {
        throw FirebaseFunctionsException(
            code: 'deadline-exceeded', message: 'Timed out');
      }
      return 'same-rematch';
    });
    addTearDown(routes.dispose);
    await tester.pumpWidget(app(routes));
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(find.text('Не удалось предложить реванш. Повторите позже.'),
        findsOneWidget);
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(ids.length, 2);
    expect(ids[1], ids[0]);
    expect(find.text('waiting:same-rematch'), findsOneWidget);
  });
  testWidgets(
      'an explicitly cancelled old request gets a new identity only after a new confirmation',
      (tester) async {
    final ids = <String>[];
    final routes = router((source, id) async {
      ids.add(id);
      if (ids.length == 1) {
        throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Cancelled',
            details: const {'reason': 'REMATCH_PREVIOUS_CANCELLED'});
      }
      return 'new-rematch';
    });
    addTearDown(routes.dispose);
    await tester.pumpWidget(app(routes));
    await confirm(tester);
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(ids.length, 2);
    expect(ids[1], isNot(ids[0]));
  });
}
