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
    final winnerKey = (aiResult['winnerKey'] ?? 'draw').toString();
    final scoreA = ((aiResult['scoreA'] as num?)?.toInt() ?? 50).clamp(0, 100);
    final scoreB = ((aiResult['scoreB'] as num?)?.toInt() ?? 50).clamp(0, 100);
    final reasoning = (aiResult['reasoning'] ?? '').toString();

    final winnerLabel = winnerKey == 'fighter1'
        ? fighter1Name
        : winnerKey == 'fighter2'
            ? fighter2Name
            : 'Ничья';

    final total = scoreA + scoreB;
    final leftFlex = total == 0 ? 1 : scoreA;
    final rightFlex = total == 0 ? 1 : scoreB;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Вердикт ИИ',
            textAlign: TextAlign.center,
            style: TextStyle(
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
