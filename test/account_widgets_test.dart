import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/services/account_service.dart';
import 'package:verdict/widgets/account_security_card.dart';
import 'package:verdict/widgets/email_account_dialog.dart';
import 'account_service_test.dart' show TestAuth, TestUser;

Widget host(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(body: child));

Future<void> fill(WidgetTester tester,
    {String confirmation = 'safe-password'}) async {
  await tester.enterText(
      find.byKey(const ValueKey('account-email')), 'fighter@example.test');
  await tester.enterText(
      find.byKey(const ValueKey('account-password')), 'safe-password');
  await tester.enterText(
      find.byKey(const ValueKey('account-password-confirm')), confirmation);
}

void main() {
  testWidgets(
      'unconfigured Google is disabled with email available as an alternative',
      (tester) async {
    final service =
        AccountService(auth: TestAuth(TestUser('guest')), googleEnabled: false);
    await tester.pumpWidget(host(AccountSecurityCard(service: service)));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Привязать Google'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Привязать почту'))
            .onPressed,
        isNotNull);
    expect(find.text('Google пока недоступен. Можно использовать почту.'),
        findsOneWidget);
  });
  testWidgets(
      'saving by email closes the form, retains the fighter and offers verification',
      (tester) async {
    final user = TestUser('original-fighter');
    final auth = TestAuth(user);
    await tester.pumpWidget(
        host(AccountSecurityCard(service: AccountService(auth: auth))));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Привязать почту'));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить аккаунт'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailAccountDialog), findsNothing);
    expect(find.text('Отправить письмо'), findsOneWidget);
    expect(auth.currentUser!.uid, 'original-fighter');
    expect(auth.logins, 0);
    expect(user.credentials.length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mismatched password confirmation never calls Firebase linking',
      (tester) async {
    final user = TestUser('guest');
    await tester.pumpWidget(host(EmailAccountDialog(
        service: AccountService(auth: TestAuth(user)), linking: true)));
    await fill(tester, confirmation: 'different');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('Пароли не совпадают.'), findsOneWidget);
    expect(user.credentials, isEmpty);
  });

  testWidgets('an occupied email leaves the form open and retains the guest',
      (tester) async {
    final user = TestUser('guest')
      ..linkError = FirebaseAuthException(code: 'email-already-in-use');
    final auth = TestAuth(user);
    await tester.pumpWidget(host(EmailAccountDialog(
        service: AccountService(auth: auth), linking: true)));
    await fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить аккаунт'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailAccountDialog), findsOneWidget);
    expect(find.textContaining('Этот способ входа'), findsOneWidget);
    expect(auth.currentUser!.uid, 'guest');
    expect(user.isAnonymous, isTrue);
    expect(auth.logins, 0);
  });

  testWidgets(
      'Google linking blocks session changes until the picker is cancelled',
      (tester) async {
    final user = TestUser('guest');
    final picker = Completer<AuthCredential?>();
    final service =
        AccountService(auth: TestAuth(user), googlePicker: () => picker.future);
    await tester.pumpWidget(host(AccountSecurityCard(service: service)));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Привязать Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    picker.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(user.isAnonymous, isTrue);
    expect(user.credentials, isEmpty);
  });

  testWidgets('link form fits a narrow phone with an open keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 640),
            viewInsets: EdgeInsets.only(bottom: 240),
            textScaler: TextScaler.linear(1.3)),
        child: EmailAccountDialog(
            service: AccountService(auth: TestAuth(TestUser('guest'))),
            linking: true))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
