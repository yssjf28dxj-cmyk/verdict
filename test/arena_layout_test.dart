import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
// Test-only SDK initialization; no account or cloud calls are made.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/screens/home_screen.dart';
import 'package:verdict/utils/arena_theme.dart';
import 'package:verdict/widgets/debate_card.dart';
import 'package:verdict/widgets/home_search_bar.dart';

// A read-only SDK test double for presentation only; production uses real snapshots.
// ignore: subtype_of_sealed_class
class FeedDocument extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FeedDocument(this.fields);
  final Map<String, dynamic> fields;
  @override
  String get id => 'arena-layout-debate';
  @override
  Map<String, dynamic> data() => fields;
}

Map<String, dynamic> debate(String status) => {
      'status': status,
      'topic':
          'A long debate topic that should stay readable on a narrow phone',
      'fighter1': 'alice',
      'fighter2': status == 'waiting' ? '' : 'bob',
      'creatorId': 'alice',
      'fighter1Name': 'First participant with a long name',
      'fighter2Name': 'Second participant with a long name',
      'visibilityMode': 'public',
      'languageCode': 'ar',
      'region': 'europe_africa',
      'roundIndex': 3,
      'currentRound': 1,
      'totalRounds': 5,
      'votes1': 31,
      'votes2': 42,
      'viewerCount': 12345,
    };
Widget host(Widget child,
        {Locale locale = const Locale('ru'),
        double scale = 2,
        double keyboardInset = 0}) =>
    MaterialApp(
      key: ValueKey('${locale.languageCode}-$scale'),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ArenaTheme.from(ThemeData.dark(useMaterial3: true)),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboardInset)),
          child: child!),
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  testWidgets(
      'arena cards fit seven locales and enlarged text on phone and tablet',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(320, 740), const Size(1024, 768)]) {
      tester.view.physicalSize = size;
      for (final locale in AppLocalizations.supportedLocales) {
        for (final status in ['waiting', 'active', 'finished']) {
          await tester.pumpWidget(host(
              Scaffold(
                  body: SingleChildScrollView(
                      child: DebateCard(
                key: ValueKey('$status-${locale.languageCode}-$size'),
                doc: FeedDocument(debate(status)),
                currentUid: 'alice',
                canEnter: true,
              ))),
              locale: locale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$locale $status $size');
          expect(
              tester
                  .getSize(find
                      .descendant(
                          of: find.byType(DebateCard),
                          matching: find.byType(Material))
                      .first)
                  .width,
              lessThanOrEqualTo(808));
        }
      }
    }
  });
  testWidgets(
      'canonical round and localized participant action are visible; spectator action differs',
      (tester) async {
    await tester.pumpWidget(host(
        Scaffold(
            body: SingleChildScrollView(
                child: DebateCard(
          doc: FeedDocument(debate('active')),
          currentUid: 'alice',
          canEnter: true,
        ))),
        scale: 1));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(DebateCard));
    final l10n = AppLocalizations.of(context)!;
    expect(find.text(l10n.roundProgress(3, 5)), findsOneWidget);
    expect(find.text(l10n.continueDebate), findsOneWidget);
    await tester.pumpWidget(host(
        Scaffold(
            body: SingleChildScrollView(
                child: DebateCard(
          key: const ValueKey('spectator'),
          doc: FeedDocument(debate('active')),
          currentUid: 'viewer',
          canEnter: true,
        ))),
        scale: 1));
    await tester.pumpAndSettle();
    expect(find.text(l10n.watchAndVote), findsOneWidget);
    expect(find.text(l10n.continueDebate), findsNothing);
  });
  testWidgets('search and expandable filters preserve selection and callbacks',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var language = 'all', region = 'global', query = '';
    await tester.pumpWidget(host(
        Scaffold(
            body: SingleChildScrollView(
                child: StatefulBuilder(
          builder: (context, update) => HomeSearchBar(
            searchController: controller,
            feedLanguage: language,
            feedRegion: region,
            onSearchChanged: (value) => query = value,
            onLanguageChanged: (value) => update(() => language = value),
            onRegionChanged: (value) => update(() => region = value),
          ),
        ))),
        scale: 1));
    await tester.enterText(find.byType(TextField), 'Search topic');
    expect(query, 'Search topic');
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    final languageField = find.byKey(const ValueKey('language-all'));
    await tester.ensureVisible(languageField);
    await tester.tap(languageField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EN').last);
    await tester.pumpAndSettle();
    expect(language, 'en');
    expect(region, 'global');
    expect(controller.text, 'Search topic');
  });
  testWidgets(
      'expanded filters fit all locales with 200% text on a narrow phone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(host(
          Scaffold(
              body: SingleChildScrollView(
            child: HomeSearchBar(
                searchController: controller,
                feedLanguage: 'all',
                feedRegion: 'europe_africa',
                onSearchChanged: (_) {},
                onLanguageChanged: (_) {},
                onRegionChanged: (_) {}),
          )),
          locale: locale));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final region = find.byKey(const ValueKey('region-europe_africa'));
      await tester.ensureVisible(region);
      await tester.tap(region);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: locale.languageCode);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });
  testWidgets(
      'home shell keeps feed accessible with keyboard in landscape and large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(320, 740), const Size(740, 360)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(host(
          const HomeScreen(debateList: Center(child: Text('Feed preview'))),
          keyboardInset: 120));
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.text('Feed preview'), findsOneWidget);
    }
  });
}
