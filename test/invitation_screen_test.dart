import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/screens/invitation_screen.dart';
import 'account_service_test.dart' show TestUser;

Widget host(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child);

void main() {
  testWidgets('waits for restored auth before constructing a protected lobby',
      (tester) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);
    var reads = 0;
    await tester.pumpWidget(host(InvitationScreen(
        debateId: 'a',
        authChanges: auth.stream,
        lobbyBuilder: (id) {
          reads++;
          return const Text('permitted lobby');
        })));
    expect(reads, 0);
    auth.add(TestUser('existing-fighter'));
    await tester.pump();
    expect(find.text('permitted lobby'), findsOneWidget);
    expect(reads, greaterThan(0));
  });
  testWidgets(
      'signed-out invitation preserves its destination when opening login',
      (tester) async {
    var reads = 0;
    final router = GoRouter(initialLocation: '/invite/abc', routes: [
      GoRoute(
          path: '/invite/:id',
          builder: (_, state) => InvitationScreen(
              debateId: state.pathParameters['id']!,
              authChanges: Stream<User?>.value(null),
              lobbyBuilder: (_) {
                reads++;
                return const Text('private data');
              })),
      GoRoute(
          path: '/auth',
          builder: (_, state) =>
              Text(state.uri.queryParameters['returnTo'] ?? 'lost')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router));
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('/invite/abc'), findsOneWidget);
    expect(reads, 0);
  });
  testWidgets(
      'invalid locator and auth error never query protected debate data',
      (tester) async {
    var reads = 0;
    Widget build(String id, Stream<User?> stream) => host(InvitationScreen(
        key: ValueKey(id),
        debateId: id,
        authChanges: stream,
        lobbyBuilder: (_) {
          reads++;
          return const Text('private data');
        }));
    await tester.pumpWidget(build('../secret', const Stream.empty()));
    await tester.pump();
    expect(find.text('Вызов удалён или недоступен этому аккаунту.'),
        findsOneWidget);
    await tester.pumpWidget(
        build('valid', Stream.error(StateError('auth unavailable'))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Не удалось загрузить вызов. Проверьте соединение и повторите попытку.'),
        findsOneWidget);
    expect(reads, 0);
  });
}
