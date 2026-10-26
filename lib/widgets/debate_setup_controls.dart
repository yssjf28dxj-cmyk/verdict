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
          label:
              '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
          semanticFormatterCallback: (value) {
            final seconds = durations[value.round()];
            return '${l10n.roundTimeLabel}: ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
          },
          activeColor: colors.primary,
          onChanged:
              enabled ? (value) => onDuration(durations[value.round()]) : null),
      const SizedBox(height: 12),
      Text(l10n.roundsLabel, style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final option in <int, String>{
          1: l10n.oneRound,
          3: l10n.threeRounds,
          5: l10n.fiveRounds,
        }.entries)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: ChoiceChip(
              key: ValueKey('rounds-${option.key}'),
              label: Text(option.value),
              selected: rounds == option.key,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              onSelected: enabled ? (_) => onRounds(option.key) : null,
            ),
          ),
      ]),
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
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final option in <String, String>{
          'public': l10n.publicMode,
          'request_only': l10n.requestOnly,
          'private': l10n.privateMode,
        }.entries)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: ChoiceChip(
              key: ValueKey('visibility-${option.key}'),
              label: Text(option.value),
              selected: visibility == option.key,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              onSelected: enabled ? (_) => onVisibility(option.key) : null,
            ),
          ),
      ]),
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
