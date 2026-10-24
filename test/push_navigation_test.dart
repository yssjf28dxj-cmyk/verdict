import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:verdict/utils/push_destination.dart';
import 'package:verdict/utils/startup_route.dart';

class Startup extends StatefulWidget {
  const Startup({super.key});
  @override
  State<Startup> createState() => _StartupState();
}

class _StartupState extends State<Startup> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (mounted && mayCompleteStartup(GoRouter.of(context))) {
        GoRouter.of(context).go('/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) => const Text('startup');
}

void main() {
  testWidgets(
      'opening a push replaces startup so a delayed splash redirect cannot cover it',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, state) => const Startup()),
      GoRoute(path: '/home', builder: (_, state) => const Text('home')),
      GoRoute(
          path: '/lobby/:id',
          builder: (_, state) => Text('battle:${state.pathParameters['id']}'))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    final now = DateTime.now().millisecondsSinceEpoch;
    final target = PushDestination.parse({
      'notificationId': 'a' * 64,
      'uid': 'alice',
      'debateId': 'safe',
      'kind': 'turn',
      'expiresAtMs': now + 60000
    }, 'alice', now)!;
    openPushDestination(router, target, 'alice');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('battle:safe'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });
  testWidgets('a tap after expiry or an account change does not navigate',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, state) => const Text('stay'))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final target = PushDestination.parse({
      'notificationId': 'a' * 64,
      'uid': 'alice',
      'debateId': 'safe',
      'kind': 'turn',
      'expiresAtMs': 2000
    }, 'alice', 1000)!;
    openPushDestination(router, target, 'bob', nowMs: 1000);
    openPushDestination(router, target, 'alice', nowMs: 2000);
    await tester.pumpAndSettle();
    expect(find.text('stay'), findsOneWidget);
  });
}
