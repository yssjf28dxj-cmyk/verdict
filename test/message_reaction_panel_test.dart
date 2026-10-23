import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/services/message_reaction_service.dart';
import 'package:verdict/widgets/message_reaction_panel.dart';

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
        home: Scaffold(body: child));
void main() {
  testWidgets('fighters see counts but have no reaction controls enabled',
      (tester) async {
    var writes = 0;
    await tester.pumpWidget(app(MessageReactionPanel(
        debateId: 'battle',
        messageId: 'message',
        changes: Stream.value(
            const MessageReactionView(strongCount: 8, sourceCount: 3)),
        send: (_, active, revision, id) async {
          writes++;
        })));
    await tester.pumpAndSettle();
    expect(find.text('Сильный аргумент · 8'), findsOneWidget);
    expect(find.text('Нужен источник · 3'), findsOneWidget);
    for (final button
        in tester.widgetList<OutlinedButton>(find.byType(OutlinedButton))) {
      expect(button.onPressed, isNull);
    }
    expect(writes, 0);
  });
  testWidgets(
      'pending request blocks double presses and selected state follows server updates',
      (tester) async {
    final updates = StreamController<MessageReactionView>.broadcast();
    addTearDown(updates.close);
    final pending = Completer<void>();
    var writes = 0;
    await tester.pumpWidget(app(MessageReactionPanel(
        debateId: 'battle',
        messageId: 'message',
        changes: updates.stream,
        send: (kind, active, revision, id) {
          writes++;
          expect(kind, 'strong');
          expect(active, true);
          expect(revision, 0);
          return pending.future;
        })));
    updates.add(const MessageReactionView(canReact: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сильный аргумент · 0'));
    await tester.pump();
    expect(writes, 1);
    expect(
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton).first)
            .onPressed,
        isNull);
    pending.complete();
    updates.add(const MessageReactionView(
        canReact: true, strong: true, strongCount: 1, strongRevision: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Сильный аргумент · 1'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
  testWidgets(
      'lost acknowledgement retries the original desired value and request identity',
      (tester) async {
    final updates = StreamController<MessageReactionView>.broadcast();
    addTearDown(updates.close);
    final ids = <String>[];
    await tester.pumpWidget(app(MessageReactionPanel(
        debateId: 'battle',
        messageId: 'message',
        changes: updates.stream,
        send: (kind, active, revision, id) async {
          ids.add(id);
          expect(active, true);
          expect(revision, 0);
          if (ids.length == 1) {
            updates.add(const MessageReactionView(
                canReact: true,
                strong: true,
                strongCount: 1,
                strongRevision: 1));
            throw FirebaseFunctionsException(
                code: 'deadline-exceeded', message: 'Lost response');
          }
        })));
    updates.add(const MessageReactionView(canReact: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сильный аргумент · 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сильный аргумент · 1'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(ids.length, 2);
    expect(ids[1], ids[0]);
  });
  testWidgets('access errors hide previous counts and disable writing',
      (tester) async {
    final updates = StreamController<MessageReactionView>.broadcast();
    addTearDown(updates.close);
    await tester.pumpWidget(app(MessageReactionPanel(
        debateId: 'battle',
        messageId: 'message',
        changes: updates.stream,
        send: (_, active, revision, id) async {})));
    updates.add(const MessageReactionView(canReact: true, strongCount: 17));
    await tester.pumpAndSettle();
    expect(find.text('Сильный аргумент · 17'), findsOneWidget);
    updates.addError(StateError('access revoked'));
    await tester.pumpAndSettle();
    expect(find.text('Сильный аргумент · 17'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
  testWidgets('an unavailable initial stream stops loading and offers retry',
      (tester) async {
    final updates = StreamController<MessageReactionView>.broadcast();
    addTearDown(updates.close);
    await tester.pumpWidget(app(MessageReactionPanel(
        debateId: 'battle',
        messageId: 'message',
        changes: updates.stream,
        send: (_, active, revision, id) async {})));
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    updates.add(const MessageReactionView(canReact: true));
    await tester.pumpAndSettle();
    expect(find.text('Сильный аргумент · 0'), findsOneWidget);
  });
  testWidgets('finished battle update disables spectator controls',
      (tester) async {
    final updates = StreamController<MessageReactionView>.broadcast();
    addTearDown(updates.close);
    await tester.pumpWidget(app(MessageReactionPanel(
        debateId: 'battle',
        messageId: 'message',
        changes: updates.stream,
        send: (_, active, revision, id) async {})));
    updates.add(const MessageReactionView(canReact: true));
    await tester.pumpAndSettle();
    updates.add(const MessageReactionView(canReact: false));
    await tester.pumpAndSettle();
    for (final button
        in tester.widgetList<OutlinedButton>(find.byType(OutlinedButton))) {
      expect(button.onPressed, isNull);
    }
  });
  for (final language in ['ru', 'en', 'ar', 'es', 'fr', 'hi', 'zh']) {
    testWidgets('reaction sheet fits a narrow phone with large $language text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(
          MessageReactionPanel(
              debateId: 'battle',
              messageId: 'message',
              changes: Stream.value(const MessageReactionView(
                  canReact: true, strongCount: 100000)),
              send: (_, active, revision, id) async {}),
          language: language,
          scale: 1.6));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
