import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/arena_theme.dart';

/// Presentation only: the room supplies its server-derived time and permissions.
class DebateTurnHeader extends StatelessWidget {
  const DebateTurnHeader(
      {super.key,
      required this.fighter1,
      required this.fighter2,
      required this.statusLabel,
      required this.remainingSeconds,
      required this.active,
      required this.round,
      required this.totalRounds,
      required this.votes1,
      required this.votes2,
      this.viewers,
      this.compact = false,
      this.bank1Seconds,
      this.bank2Seconds,
      this.activeSide = 0,
      this.onHandoff,
      this.onAccept,
      this.accepting = false});
  final String fighter1, fighter2, statusLabel;
  final int remainingSeconds, round, totalRounds, votes1, votes2, activeSide;
  final int? viewers, bank1Seconds, bank2Seconds;
  final bool active, compact, accepting;
  final VoidCallback? onHandoff, onAccept;
  static String clock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    return '${(safe ~/ 60).toString().padLeft(2, '0')}:${(safe % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final left = votes1 < 0 ? 0 : votes1;
    final right = votes2 < 0 ? 0 : votes2;
    return Container(
      key: const ValueKey('debate-turn-header'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: ArenaTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ArenaTheme.border)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(statusLabel,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                Semantics(
                    label: l10n.roundTimeLabel,
                    child: Text(active ? clock(remainingSeconds) : '--:--',
                        key: const ValueKey('active-turn-clock'),
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: active && remainingSeconds <= 10
                                ? ArenaTheme.red
                                : Colors.white))),
              ]),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(l10n.roundProgress(round, totalRounds),
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final side in [1, 2])
                Expanded(
                    child: Padding(
                  padding: EdgeInsetsDirectional.only(end: side == 1 ? 12 : 0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                  activeSide == side
                                      ? Icons.record_voice_over_outlined
                                      : Icons.person_outline,
                                  size: 20,
                                  color: side == 1
                                      ? ArenaTheme.blue
                                      : ArenaTheme.red),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(side == 1 ? fighter1 : fighter2,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600))),
                            ]),
                        if ((side == 1 ? bank1Seconds : bank2Seconds) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                '${l10n.timeBankLabel}: +${clock((side == 1 ? bank1Seconds : bank2Seconds)!)}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ),
                      ]),
                )),
            ]),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 4, children: [
            Text('$fighter1: $left',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ArenaTheme.blue, fontSize: 12)),
            Text('$fighter2: $right',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ArenaTheme.red, fontSize: 12)),
            if (!compact)
              Text(
                  viewers == null
                      ? '— ${l10n.spectatorsLiveLabel}'
                      : '≈${l10n.viewersCount(viewers!)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(children: [
                Expanded(
                    flex: left + right == 0 ? 1 : left,
                    child: const SizedBox(
                        height: 4, child: ColoredBox(color: ArenaTheme.blue))),
                Expanded(
                    flex: left + right == 0 ? 1 : right,
                    child: const SizedBox(
                        height: 4, child: ColoredBox(color: ArenaTheme.red))),
              ])),
          if (!compact && onHandoff != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                  onPressed: onHandoff,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(l10n.passTurn),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
            ),
          if (onAccept != null || accepting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(
                  onPressed: accepting ? null : onAccept,
                  child:
                      Text(accepting ? l10n.accepting : l10n.acceptChallenge)),
            ),
        ],
      ),
    );
  }
}
