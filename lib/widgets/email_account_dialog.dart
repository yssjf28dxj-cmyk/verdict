import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/account_service.dart';
import '../utils/account_error.dart';

class EmailAccountDialog extends StatefulWidget {
  const EmailAccountDialog(
      {super.key, required this.service, required this.linking});
  final AccountService service;
  final bool linking;
  @override
  State<EmailAccountDialog> createState() => _EmailAccountDialogState();
}

class _EmailAccountDialogState extends State<EmailAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _resetSent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.linking) {
        await widget.service.linkEmail(_email.text, _password.text);
      } else {
        await widget.service.signInEmail(_email.text, _password.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = accountError(AppLocalizations.of(context)!, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    if (!_email.text.trim().contains('@')) {
      setState(() => _error = l10n.accountEmailInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.resetPassword(_email.text);
      if (mounted) setState(() => _resetSent = true);
    } on FirebaseAuthException catch (error) {
      // Do not reveal whether an email has an account.
      if (mounted) {
        setState(() {
          if (error.code == 'user-not-found') {
            _resetSent = true;
          } else {
            _error = accountError(l10n, error);
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = accountError(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text(
              widget.linking ? l10n.accountSaveTitle : l10n.accountEmailSignIn),
          content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: AutofillGroup(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.linking) ...[
                          Text(l10n.accountSaveHint),
                          const SizedBox(height: 16)
                        ],
                        TextFormField(
                            key: const ValueKey('account-email'),
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            textCapitalization: TextCapitalization.none,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                                labelText: l10n.accountEmailLabel),
                            validator: (value) =>
                                value != null && value.trim().contains('@')
                                    ? null
                                    : l10n.accountEmailInvalid),
                        const SizedBox(height: 12),
                        TextFormField(
                            key: const ValueKey('account-password'),
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [
                              widget.linking
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password
                            ],
                            decoration: InputDecoration(
                                labelText: l10n.accountPasswordLabel,
                                helperText: widget.linking
                                    ? l10n.accountPasswordHint
                                    : null,
                                helperMaxLines: 2),
                            validator: (value) => value == null ||
                                    value.isEmpty ||
                                    (widget.linking && value.length < 8)
                                ? l10n.accountPasswordHint
                                : null),
                        if (widget.linking) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                              key: const ValueKey('account-password-confirm'),
                              controller: _confirmation,
                              enabled: !_busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                  labelText: l10n.accountPasswordConfirm),
                              validator: (value) => value == _password.text
                                  ? null
                                  : l10n.accountPasswordMismatch),
                        ],
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        if (_resetSent)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(l10n.accountResetSent)),
                        if (!widget.linking)
                          TextButton(
                              onPressed: _busy || _resetSent ? null : _reset,
                              child: Text(l10n.accountResetPassword)),
                      ]))))),
          actions: [
            TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                child: Text(l10n.accountCancel)),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.linking
                        ? l10n.accountSaveTitle
                        : l10n.accountEmailSignIn)),
          ],
        ));
  }
}
