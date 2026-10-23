import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/l10n/app_localizations.dart';
import 'package:verdict/utils/ai_verdict_state.dart';
import 'package:verdict/utils/pending_message_request.dart';
import 'package:verdict/utils/vote_totals.dart';
import 'package:verdict/widgets/ai_result_card.dart';

void main() {
  const verdict = <String, dynamic>{
    'status': 'ready',
    'winnerKey': 'fighter1',
    'scoreA': 75,
    'scoreB': 25,
  };

  test('only a complete finite result can be displayed as an AI verdict', () {
    expect(hasValidAiVerdict(verdict), isTrue);
    for (final overrides in <Map<String, dynamic>>[
      {'error': true},
      {'status': 'unavailable'},
      {'status': 'insufficient_content'},
      {'reason': 'no_content'},
      {'winnerKey': 'unknown'},
      {'scoreA': null},
      {'scoreA': double.nan},
      {'scoreB': double.infinity},
      {'scoreB': -1},
      {'scoreA': 101},
    ]) {
      expect(hasValidAiVerdict({...verdict, ...overrides}), isFalse,
          reason: overrides.toString());
    }
  });

  test('retry after an ambiguous send reuses the same request identifier', () {
    var next = 0;
    final requests = PendingMessageRequest(createId: () => 'id-${++next}');
    final first = requests.forText(' hello ');
    expect(requests.forText('hello').id, first.id);
    requests.confirmed(first);
    expect(requests.forText('hello').id, isNot(first.id));
  });

  test('a late acknowledgement cannot discard the newer draft identifier', () {
    var next = 0;
    final requests = PendingMessageRequest(createId: () => 'id-${++next}');
    final first = requests.forText('first');
    final newer = requests.forText('new draft');
    requests.confirmed(first);
    expect(requests.forText('new draft').id, newer.id);
    expect(() => requests.forText('  '), throwsArgumentError);
  });

  test('all 16 public shards contribute while malformed counts are ignored', () {
    final totals = VoteTotals.fromShards([
      ...List.generate(16, (_) => {'votes1': 1, 'votes2': 2}),
      {'votes1': -3, 'votes2': double.infinity},
      {'votes1': '100', 'votes2': 1.5},
      {'metadata': 10000},
    ]);
    expect(totals.votes1, 16);
    expect(totals.votes2, 32);
    final empty = VoteTotals.fromShards([]);
    expect([empty.votes1, empty.votes2], [0, 0]);
  });

  for (final reason in ['not_configured', 'no_content', 'unavailable']) {
    testWidgets('AI error $reason is explained without a fabricated draw', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: AiResultCard(
          aiResult: {'error': true, 'reason': reason, 'winnerKey': 'draw',
            'scoreA': 50, 'scoreB': 50},
          fighter1Name: 'First',
          fighter2Name: 'Second',
        )),
      ));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AiResultCard));
      final l10n = AppLocalizations.of(context)!;
      final message = reason == 'not_configured' ? l10n.aiJudgeNotConfigured
          : reason == 'no_content' ? l10n.aiJudgeInsufficientContent
          : l10n.aiJudgeUnavailable;
      expect(find.text(message), findsOneWidget);
      expect(find.text(l10n.draw), findsNothing);
      expect(find.text('50'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
