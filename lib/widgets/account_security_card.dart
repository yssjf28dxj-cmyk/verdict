import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/account_service.dart';
import '../utils/account_error.dart';
import '../utils/compact_notice.dart';
import 'email_account_dialog.dart';

class AccountSecurityCard extends StatefulWidget {
  const AccountSecurityCard({super.key, this.service});
  final AccountService? service;
  @override
  State<AccountSecurityCard> createState() => _AccountSecurityCardState();
}

class _AccountSecurityCardState extends State<AccountSecurityCard> {
  late final _service = widget.service ?? AccountService();
  bool _busy = false;

  Future<bool> _linkGoogle() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final title = AppLocalizations.of(context)!.accountLinkGoogle;
    // Prevent signing out or switching test profiles while the native Firebase
    // link is in flight. Cancelling the Google picker still returns normally.
    final dialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
                title: Text(title),
                content: const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator())))));
    try {
      return await _service.linkGoogle() != null;
    } finally {
      navigator.pop();
      await dialog;
    }
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await action() && mounted) {
        showCompactNotice(context, AppLocalizations.of(context)!.accountSaved);
      }
    } catch (error) {
      if (mounted) {
        showCompactNotice(
            context, accountError(AppLocalizations.of(context)!, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder(
        stream: _service.auth.userChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data ?? _service.auth.currentUser;
          if (user == null) return const SizedBox.shrink();
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            user.isAnonymous
                                ? l10n.accountSaveTitle
                                : l10n.accountSaved,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (user.isAnonymous) ...[
                          Text(l10n.accountSaveHint),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: _busy || !_service.googleAvailable
                                  ? null
                                  : () => _run(_linkGoogle),
                              icon: const Icon(Icons.link),
                              label: Text(l10n.accountLinkGoogle)),
                          if (!_service.googleAvailable)
                            Text(l10n.accountGoogleUnavailable,
                                style: Theme.of(context).textTheme.bodySmall),
                          OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async =>
                                      await showDialog<bool>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (_) => EmailAccountDialog(
                                              service: _service,
                                              linking: true)) ==
                                      true),
                              icon: const Icon(Icons.email_outlined),
                              label: Text(l10n.accountLinkEmail)),
                        ] else if (user.providerData.any((provider) =>
                            provider.providerId == 'password')) ...[
                          Text(user.emailVerified
                              ? l10n.accountEmailVerified
                              : l10n.accountVerificationHint),
                          if (!user.emailVerified)
                            Wrap(spacing: 8, children: [
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          setState(() => _busy = true);
                                          try {
                                            await _service.sendVerification();
                                            if (context.mounted) {
                                              showCompactNotice(context,
                                                  l10n.accountVerificationSent);
                                            }
                                          } catch (error) {
                                            if (context.mounted) {
                                              showCompactNotice(context,
                                                  accountError(l10n, error));
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _busy = false);
                                            }
                                          }
                                        },
                                  child: Text(l10n.accountSendVerification)),
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          setState(() => _busy = true);
                                          try {
                                            await _service.refresh();
                                          } catch (error) {
                                            if (context.mounted) {
                                              showCompactNotice(context,
                                                  accountError(l10n, error));
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _busy = false);
                                            }
                                          }
                                        },
                                  child: Text(l10n.accountCheckVerification)),
                            ]),
                        ],
                        if (_busy && !user.isAnonymous)
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(minHeight: 2)),
                      ])));
        });
  }
}
