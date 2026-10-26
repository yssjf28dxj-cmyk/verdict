import 'package:firebase_core/firebase_core.dart';
// Test-only SDK initialization; no account or backend is contacted.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/screens/create_debate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());

  testWidgets(
      'creation form remains readable on phones and tablets in every locale',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(320, 740), const Size(1024, 768)]) {
      tester.view.physicalSize = size;
      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(MaterialApp(
          key: ValueKey('$size-${locale.languageCode}'),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 180)),
              child: child!),
          home: const CreateDebateScreen(),
        ));
        await tester.pumpAndSettle();
        final publish = find.byType(ElevatedButton);
        await tester.ensureVisible(publish);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${locale.languageCode}, $size, 200% text with keyboard');
        final form = tester.getSize(find.byType(Form));
        expect(form.width, lessThanOrEqualTo(680));
        expect(tester.getSize(publish).height, greaterThanOrEqualTo(54));
      }
    }
  });
}
