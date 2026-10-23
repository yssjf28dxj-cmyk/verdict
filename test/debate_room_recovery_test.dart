import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:cloud_firestore_platform_interface/src/method_channel/utils/firestore_message_codec.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:verdict/widgets/debate_input_bar.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/screens/debate_room_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  testWidgets(
      'leaving during profile hydration cannot revive the room or attach listeners',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final hydration = Completer<void>();
    var profileReads = 0;
    var listenerStarts = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'com.llfbandit.record/messages',
      'simform_audio_waveforms'
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(name), (_) async => null);
    }
    const listenChannel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceSnapshot',
        FirebaseFirestoreHostApi.codec);
    messenger.setMockDecodedMessageHandler<Object?>(listenChannel, (_) async {
      listenerStarts++;
      return ['unused'];
    });
    const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet',
        FirebaseFirestoreHostApi.codec);
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      final request = (message as List)[1] as DocumentReferenceRequest;
      if (request.path.startsWith('users/')) {
        profileReads++;
        await hydration.future;
      }
      return [
        PigeonDocumentSnapshot(
            path: request.path,
            metadata: PigeonSnapshotMetadata(
                hasPendingWrites: false, isFromCache: false),
            data: request.path.startsWith('users/')
                ? {'name': 'Synthetic'}
                : {
                    'status': 'active',
                    'visibilityMode': 'public',
                    'fighter1': 'alice',
                    'fighter2': 'bob',
                    'activeSpeakerId': 'alice',
                    'roundIndex': 1,
                  })
      ];
    });
    await tester.pumpWidget(const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DebateRoomScreen(debateId: 'synthetic-room')));
    await tester.pump();
    expect(profileReads, 1);
    await tester.pumpWidget(const SizedBox());
    hydration.complete();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(listenerStarts, 0);
    messenger.setMockDecodedMessageHandler<Object?>(listenChannel, null);
    messenger.setMockDecodedMessageHandler<Object?>(channel, null);
  });
  for (final initialCached in [false, true]) {
    testWidgets(
        'cached turns, resume, expiry and offline finish (initial cache=$initialCached)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in [
        'com.llfbandit.record/messages',
        'simform_audio_waveforms'
      ]) {
        messenger.setMockMethodCallHandler(
            MethodChannel(name), (_) async => null);
      }
      final deadline =
          Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 2)));
      Map<String?, Object?> data(int round) => {
            'status': 'active',
            'visibilityMode': 'public',
            'fighter1': 'alice',
            'fighter2': 'bob',
            'fighter1Name': 'Alice',
            'fighter2Name': 'Bob',
            'activeSpeakerId': 'alice',
            'roundIndex': round,
            'isRoundActive': true,
            'roundEndsAt': deadline,
          };
      PigeonDocumentSnapshot snapshot(int round, bool cache) =>
          PigeonDocumentSnapshot(
              path: 'debates/synthetic-room',
              data: data(round),
              metadata: PigeonSnapshotMetadata(
                  hasPendingWrites: false, isFromCache: cache));
      const getName =
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet';
      const listenName =
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceSnapshot';
      final refresh = Completer<PigeonDocumentSnapshot>();
      var gets = 0;
      messenger.setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
              getName, FirebaseFirestoreHostApi.codec),
          (_) async => [
                ++gets == 1
                    ? snapshot(initialCached ? 9 : 3, initialCached)
                    : gets == 2
                        ? await refresh.future
                        : snapshot(7, false)
              ]);
      const codec = StandardMethodCodec(FirestoreMessageCodec());
      var roomStarts = 0, roomCancels = 0;
      final roomEvents = <String>[];
      messenger.setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
              listenName, FirebaseFirestoreHostApi.codec), (message) async {
        final args = message as List;
        final request = args[1] as DocumentReferenceRequest;
        final isRoom = request.path == 'debates/synthetic-room';
        if (isRoom) {
          expect(args[2], true); // metadata-only confirmation must arrive.
        }
        final id = isRoom ? 'room-${++roomStarts}' : 'activity';
        final name = 'plugins.flutter.io/firebase_firestore/document/$id';
        if (isRoom) roomEvents.add(name);
        messenger.setMockMethodCallHandler(MethodChannel(name, codec),
            (call) async {
          if (isRoom && call.method == 'cancel') roomCancels++;
          return null;
        });
        return [id];
      });
      final router = GoRouter(initialLocation: '/room', routes: [
        GoRoute(
            path: '/room',
            builder: (_, __) =>
                const DebateRoomScreen(debateId: 'synthetic-room')),
        GoRoute(
            path: '/result/:id',
            builder: (_, __) => const Scaffold(body: Text('server result'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router));
      await tester.idle();
      final dynamic state = tester.state(find.byType(DebateRoomScreen));
      // Exercise real screen state/SDK delivery without rendering unrelated media widgets.
      state.isLoading = true;
      expect(state.roundIndex, initialCached ? 9 : 3);
      state.currentUserId = 'alice';
      expect(state.canSendText, !initialCached);
      Future<void> deliver(PigeonDocumentSnapshot value,
          {String? channel}) async {
        messenger.handlePlatformMessage(channel ?? roomEvents.last,
            codec.encodeSuccessEnvelope(value.encode()), (_) {});
        await tester.idle();
      }

      if (initialCached) {
        await deliver(snapshot(3, false));
        expect(state.roundIndex, 3);
      }
      await deliver(snapshot(1, true));
      expect(state.roundIndex, 3);
      expect(state.canSendText, false);
      await deliver(snapshot(3, false));
      expect(state.canSendText, true);
      final pending = snapshot(3, false)
        ..metadata =
            PigeonSnapshotMetadata(hasPendingWrites: true, isFromCache: false);
      await deliver(pending);
      expect(state.canSendText, false);
      await deliver(snapshot(3, false));
      expect(state.canSendText, true);
      await deliver(snapshot(2, false));
      expect(state.roundIndex,
          3); // Even a delayed old confirmed event cannot regress.
      final previousChannel = roomEvents.last;
      state.currentUserId =
          ''; // Presence/Auth not under test; never call live services.
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.idle();
      state.currentUserId = 'alice';
      expect(roomStarts, 1);
      expect(roomCancels, 0);
      expect(gets, 2);
      expect(state.canSendText, false);
      expect(roomEvents.last,
          previousChannel); // resume keeps the same SDK subscription
      expect(state.isMyTurn,
          true); // freshness gate does not change media eligibility
      if (initialCached) {
        await deliver(snapshot(3, true));
        refresh.complete(snapshot(3, false));
        await tester.idle();
        expect(
            state.canSendText, false); // cache invalidates an older server read
      }
      final opponent = snapshot(4, false)..data!['activeSpeakerId'] = 'bob';
      await deliver(opponent);
      expect(state.roundIndex, 4);
      if (!initialCached) refresh.complete(snapshot(3, false));
      await tester.idle();
      expect(state.roundIndex,
          4); // late reconnect read cannot overwrite a stream update
      expect(state.canSendText, false);
      final expired = snapshot(5, false)
        ..data!['roundEndsAt'] = Timestamp.fromDate(
            DateTime.now().subtract(const Duration(seconds: 1)));
      state.currentUserId = '';
      await deliver(expired);
      state.currentUserId = 'alice';
      expect(state.canSendText, false);
      state.currentUserId = '';
      final ended = snapshot(6, false)..data!['status'] = 'finished';
      await deliver(ended);
      expect(state.status, 'finished');
      expect(state.canSendText, false);
      await tester.pumpAndSettle();
      expect(find.text('server result'), findsOneWidget);
      expect(roomCancels, 1);
      router.go('/room');
      await tester.pump();
      await tester.pump();
      await tester.idle();
      final dynamic reopened = tester.state(find.byType(DebateRoomScreen));
      reopened.isLoading = true;
      expect(reopened.roundIndex, 7);
      expect(roomStarts, 2);
      await tester.pumpWidget(const SizedBox());
      expect(roomCancels, 2);
      await tester.pump(const Duration(
          seconds: 2)); // drain invalidated client advance jitter
      expect(tester.takeException(), isNull);
      messenger.setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
              getName, FirebaseFirestoreHostApi.codec),
          null);
      messenger.setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
              listenName, FirebaseFirestoreHostApi.codec),
          null);
    });
  }

  testWidgets(
      'unconfirmed text does not disable existing media controls or erase draft',
      (tester) async {
    final text = TextEditingController(text: 'pending draft');
    final recorder = RecorderController();
    var images = 0, sends = 0;
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: DebateInputBar(
          isMyTurn: true,
          canSendText: false,
          isSendingMessage: false,
          isUploading: false,
          isRecording: false,
          isRoundActive: true,
          isYielding: false,
          recorderController: recorder,
          recordingStartTime: null,
          textController: text,
          onSend: () => sends++,
          onMicLongPressStart: (_) {},
          onMicLongPressEnd: (_) {},
          onPickImage: () => images++,
          onCancelRecording: () {},
          onSendRecording: () {},
        ))));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, false);
    field.onSubmitted?.call('pending draft');
    expect(sends, 0);
    await tester.tap(find.byIcon(Icons.photo_outlined));
    expect(images, 1);
    expect(text.text, 'pending draft');
    await tester.pumpWidget(const SizedBox());
    text.dispose();
    recorder.dispose();
  });
}
