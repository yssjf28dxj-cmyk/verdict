import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/models/debate_history_item.dart';
import 'package:verdict/screens/profile_history_screen.dart';

DebateHistoryItem row(String id, int day,
        {String outcome = 'WIN', String status = 'finished'}) =>
    DebateHistoryItem(
        debateId: id,
        topic: 'Topic $id',
        status: status,
        opponentLabel: 'Opponent',
        outcomeLabel: outcome,
        createdAt: DateTime(2026, 10, day));
Widget app(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child);
void main() {
  test('unfinished or undecided battles never fabricate a win or draw', () {
    final unfinished = DebateHistoryItem.fromData('a',
        {'fighter1': 'me', 'winner': 'fighter1', 'status': 'active'}, 'me');
    expect(unfinished.outcomeLabel, 'LIVE');
    final undecided = DebateHistoryItem.fromData(
        'a', {'fighter1': 'me', 'status': 'finished'}, 'me');
    expect(undecided.outcomeLabel, 'FINISHED');
  });
  test('history outcome follows the selected identity rather than a fixed side',
      () {
    final data = {
      'fighter1': 'alice',
      'fighter2': 'bob',
      'winner': 'fighter1',
      'status': 'finished',
      'fighter1Name': 'Alice',
      'fighter2Name': 'Bob'
    };
    expect(DebateHistoryItem.fromData('a', data, 'alice').outcomeLabel, 'WIN');
    final bob = DebateHistoryItem.fromData('a', data, 'bob');
    expect(bob.outcomeLabel, 'LOSS');
    expect(bob.opponentLabel, 'Alice');
  });
  testWidgets('older pages merge without duplicates and remain sorted',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(ProfileHistoryScreen(
        loadPage: (reset) async {
          calls++;
          return calls == 1 ? [row('a', 1)] : [row('a', 1), row('b', 3)];
        },
        hasMore: () => calls < 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Загрузить ещё'));
    await tester.pumpAndSettle();
    expect(find.text('Topic a'), findsOneWidget);
    expect(find.text('Topic b'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Topic b')).dy,
        lessThan(tester.getTopLeft(find.text('Topic a')).dy));
    expect(find.text('Загрузить ещё'), findsNothing);
  });
  testWidgets('failed loading can retry without a passed route snapshot',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(ProfileHistoryScreen(
        loadPage: (reset) async {
          calls++;
          if (calls == 1) throw StateError('network');
          return [row('recovered', 1)];
        },
        hasMore: () => false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('Topic recovered'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets(
      'history opens the protected lobby instead of trusting old status',
      (tester) async {
    final router = GoRouter(initialLocation: '/history', routes: [
      GoRoute(
          path: '/history',
          builder: (_, state) => ProfileHistoryScreen(
              loadPage: (_) async => [row('old', 1)], hasMore: () => false)),
      GoRoute(
          path: '/lobby/:id',
          builder: (_, state) => Text('checked:${state.pathParameters['id']}'))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Topic old'));
    await tester.pumpAndSettle();
    expect(find.text('checked:old'), findsOneWidget);
  });
  testWidgets('outcome filters apply to the loaded history', (tester) async {
    await tester.pumpWidget(app(ProfileHistoryScreen(
        loadPage: (_) async => [row('won', 1), row('lost', 2, outcome: 'LOSS')],
        hasMore: () => false)));
    await tester.pumpAndSettle();
    final losses =
        AppLocalizations.of(tester.element(find.byType(ProfileHistoryScreen)))!
            .losses;
    await tester.tap(find.text(losses));
    await tester.pumpAndSettle();
    expect(find.text('Topic lost'), findsOneWidget);
    expect(find.text('Topic won'), findsNothing);
  });
}
