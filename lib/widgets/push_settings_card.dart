import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/push_coordinator.dart';

class PushSettingsCard extends StatefulWidget {
  const PushSettingsCard({super.key, this.read, this.write});
  final Future<bool> Function()? read;
  final Future<void> Function(bool)? write;
  @override
  State<PushSettingsCard> createState() => _PushSettingsCardState();
}

class _PushSettingsCardState extends State<PushSettingsCard> {
  bool? _enabled;
  bool _busy = true, _error = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final value = await (widget.read ?? pushCoordinator.enabled)();
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await (widget.write ?? pushCoordinator.setEnabled)(value);
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.pushTitle,
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(l10n.pushHint),
                  if (_enabled != null)
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.pushEnable),
                        value: _enabled!,
                        onChanged: _busy ? null : _change),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error) Text(l10n.pushError),
                  if (_error && !_busy)
                    TextButton(
                        onPressed: _load, child: Text(l10n.retryMediaLabel)),
                  if (_enabled == true)
                    TextButton(
                        onPressed: _busy ? null : () => _change(true),
                        child: Text(l10n.pushConnectDevice)),
                  TextButton.icon(
                      onPressed: () => context.push('/notifications'),
                      icon: const Icon(Icons.notifications_outlined),
                      label: Text(l10n.pushInbox)),
                ])));
  }
}
