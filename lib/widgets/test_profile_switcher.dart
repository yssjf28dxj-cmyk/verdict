import 'package:flutter/material.dart';
import '../firebase_session.dart';
import '../l10n/app_localizations.dart';
import '../services/pending_debate_service.dart';
import '../services/push_coordinator.dart';

/// Test build only. Switching preserves the Firebase sessions in every slot.
class TestProfileSwitcher extends StatelessWidget {
  const TestProfileSwitcher({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!testProfilesEnabled) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: testProfiles,
      builder: (context, _) => PopupMenuButton<int>(
        enabled: !testProfiles.busy,
        tooltip:
            '${l10n.testProfilesTitle}: ${l10n.testProfileNumber(testProfiles.selected)}',
        initialValue: testProfiles.selected,
        onSelected: (slot) async {
          if (slot == testProfiles.selected) return;
          try {
            await pushCoordinator.beforeSessionChange();
            PendingDebateService.instance.stopWatching();
            await testProfiles.switchTo(slot);
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.testProfileSwitchFailed)),
            );
          }
        },
        itemBuilder: (context) => List.generate(6, (index) {
          final slot = index + 1;
          return CheckedPopupMenuItem<int>(
            value: slot,
            checked: slot == testProfiles.selected,
            child: Text(l10n.testProfileNumber(slot)),
          );
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (testProfiles.busy)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.switch_account_outlined, size: 20),
            const SizedBox(width: 6),
            Text(compact
                ? '${testProfiles.selected}'
                : l10n.testProfileNumber(testProfiles.selected)),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
      ),
    );
  }
}
