import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class DebateSetupControls extends StatelessWidget {
  const DebateSetupControls(
      {super.key,
      required this.duration,
      required this.rounds,
      required this.visibility,
      required this.directInvite,
      required this.onDuration,
      required this.onRounds,
      required this.onVisibility,
      required this.onDirectInvite,
      this.enabled = true});
  static const durations = [30, 60, 90, 120, 180, 300, 420, 600];
  final int duration;
  final int rounds;
  final String visibility;
  final bool directInvite;
  final bool enabled;
  final ValueChanged<int> onDuration;
  final ValueChanged<int> onRounds;
  final ValueChanged<String> onVisibility;
  final ValueChanged<bool> onDirectInvite;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text(l10n.roundTimeLabel,
                style: const TextStyle(color: Colors.white70))),
        Text('${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600))
      ]),
      Slider(
          key: const ValueKey('round-duration'),
          min: 0,
          max: 7,
          divisions: 7,
          value: durations.indexOf(duration).clamp(0, 7).toDouble(),
          label: '$duration s',
          activeColor: const Color(0xFFFFBE45),
          onChanged:
              enabled ? (value) => onDuration(durations[value.round()]) : null),
      const SizedBox(height: 12),
      Text(l10n.roundsLabel, style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 10),
      SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 1, label: Text(l10n.oneRound)),
            ButtonSegment(value: 3, label: Text(l10n.threeRounds)),
            ButtonSegment(value: 5, label: Text(l10n.fiveRounds)),
          ],
          selected: {rounds},
          onSelectionChanged:
              enabled ? (value) => onRounds(value.first) : null),
      const SizedBox(height: 20),
      SwitchListTile.adaptive(
          key: const ValueKey('direct-invite'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.directInvite,
              style: const TextStyle(color: Colors.white)),
          secondary: const Icon(Icons.person_add_alt_1_outlined,
              color: Colors.white60),
          value: directInvite,
          onChanged: enabled ? onDirectInvite : null),
      const SizedBox(height: 8),
      SegmentedButton<String>(
          showSelectedIcon: false,
          style: ButtonStyle(
              padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? colors.onSecondaryContainer
                      : Colors.white70)),
          segments: [
            ButtonSegment(
                value: 'public',
                label: Text(l10n.publicMode,
                    maxLines: 2, textAlign: TextAlign.center)),
            ButtonSegment(
                value: 'request_only',
                label: Text(l10n.requestOnly,
                    maxLines: 2, textAlign: TextAlign.center)),
            ButtonSegment(
                value: 'private',
                label: Text(l10n.privateMode,
                    maxLines: 2, textAlign: TextAlign.center)),
          ],
          selected: {visibility},
          onSelectionChanged:
              enabled ? (value) => onVisibility(value.first) : null),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.savings_outlined, color: Colors.white54, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(l10n.timeBankHint,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.4))),
      ]),
    ]);
  }
}
