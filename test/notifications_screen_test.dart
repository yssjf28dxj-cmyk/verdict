import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/screens/notifications_screen.dart';

class EmptySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
}

Widget app(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child);
void main() {
  testWidgets('inbox has a bounded initial wait and refresh can recover',
      (tester) async {
    final events =
        StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(app(
        NotificationsScreen(events: events.stream, currentUid: () => 'alice')));
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    events.add(EmptySnapshot());
    await tester.pumpAndSettle();
    expect(find.text('Уведомлений пока нет.'), findsOneWidget);
  });
  testWidgets('signed-out identity never reads the native Firebase service',
      (tester) async {
    await tester.pumpWidget(app(NotificationsScreen(
        events: const Stream.empty(), currentUid: () => null)));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
