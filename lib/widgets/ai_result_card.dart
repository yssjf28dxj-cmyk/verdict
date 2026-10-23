import '../l10n/app_localizations.dart';
import '../utils/ai_verdict_state.dart';
import 'package:flutter/material.dart';

import '../utils/style_utils.dart';

class AiResultCard extends StatelessWidget {
  final Map<String, dynamic> aiResult;
  final String fighter1Name;
  final String fighter2Name;

  const AiResultCard({
    super.key,
    required this.aiResult,
    required this.fighter1Name,
    required this.fighter2Name,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!hasValidAiVerdict(aiResult)) {
      final reason = aiVerdictUnavailableReason(aiResult);
      final message = reason == 'not_configured'
          ? l10n.aiJudgeNotConfigured
          : reason == 'no_content'
              ? l10n.aiJudgeInsufficientContent
              : l10n.aiJudgeUnavailable;
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.aiVerdictTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      );
    }
    final winnerKey = aiResult['winnerKey'].toString();
    final scoreA = ((aiResult['scoreA'] as num?)?.toInt() ?? 50).clamp(0, 100);
    final scoreB = ((aiResult['scoreB'] as num?)?.toInt() ?? 50).clamp(0, 100);
    final reasoning = (aiResult['reasoning'] ?? '').toString();

    final winnerLabel = winnerKey == 'fighter1'
        ? fighter1Name
        : winnerKey == 'fighter2'
            ? fighter2Name
            : l10n.draw;

    final total = scoreA + scoreB;
    final leftFlex = total == 0 ? 1 : scoreA;
    final rightFlex = total == 0 ? 1 : scoreB;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiVerdictTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFA500),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            winnerLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$scoreA',
                style: const TextStyle(
                  color: VerdictStyle.fighterBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: leftFlex,
                          child:
                              const ColoredBox(color: VerdictStyle.fighterBlue),
                        ),
                        Expanded(
                          flex: rightFlex,
                          child:
                              const ColoredBox(color: VerdictStyle.fighterRed),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$scoreB',
                style: const TextStyle(
                  color: VerdictStyle.fighterRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$fighter1Name vs $fighter2Name',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          if (reasoning.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              reasoning,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.left,
            ),
          ],
        ],
      ),
    );
  }
}
