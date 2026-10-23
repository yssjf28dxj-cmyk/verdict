import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/message_reaction_service.dart';
import '../utils/compact_notice.dart';
import '../utils/pending_message_request.dart';

typedef SetMessageReaction = Future<void> Function(
    String kind, bool active, int revision, String requestId);

class MessageReactionPanel extends StatefulWidget {
  const MessageReactionPanel(
      {super.key,
      required this.debateId,
      required this.messageId,
      this.changes,
      this.send});
  final String debateId, messageId;
  final Stream<MessageReactionView>? changes;
  final SetMessageReaction? send;
  @override
  State<MessageReactionPanel> createState() => _MessageReactionPanelState();
}

class _MessageReactionPanelState extends State<MessageReactionPanel> {
  MessageReactionService? _service;
  StreamSubscription<MessageReactionView>? _subscription;
  final _requests = PendingMessageRequest();
  MessageReactionView? _view;
  bool _failed = false, _busy = false;
  bool? _pendingActive;
  String? _pendingKind;
  int? _pendingRevision;
  Timer? _cooldown, _loadTimeout;
  bool _cooling = false;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription?.cancel();
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _failed = true;
          _view = null;
        });
      }
    });
    if (widget.changes == null || widget.send == null) {
      _service ??= MessageReactionService(widget.debateId, widget.messageId);
    }
    _subscription = (widget.changes ?? _service!.watch()).listen((view) {
      _loadTimeout?.cancel();
      if (mounted) {
        setState(() {
          _view = view;
          _failed = false;
        });
      }
    }, onError: (Object error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _view = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cooldown?.cancel();
    _loadTimeout?.cancel();
    super.dispose();
  }

  Future<void> _react(String kind) async {
    final view = _view;
    if (_busy || _cooling || view == null || !view.canReact) return;
    // A timeout may follow a commit. Retry the same desired value and revision,
    // rather than toggling the newly observed value in the opposite direction.
    if (_pendingKind != kind) {
      _pendingKind = kind;
      _pendingActive = !(kind == 'strong' ? view.strong : view.source);
      _pendingRevision =
          kind == 'strong' ? view.strongRevision : view.sourceRevision;
    }
    final request =
        _requests.forText('$kind:$_pendingActive:$_pendingRevision');
    setState(() => _busy = true);
    try {
      await (widget.send ?? _service!.set)(
          kind, _pendingActive!, _pendingRevision!, request.id);
      _requests.confirmed(request);
      _pendingKind = null;
      if (!mounted) return;
      setState(() => _cooling = true);
      _cooldown = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _cooling = false);
      });
    } catch (error) {
      if (error is FirebaseFunctionsException && error.code == 'resource-exhausted' && mounted) {
        setState(() => _cooling = true);
        _cooldown?.cancel();
        _cooldown = Timer(const Duration(seconds: 1), () { if (mounted) setState(() => _cooling = false); });
      }
      // Conflicting edits on another device require a new explicit intent.
      if (error is FirebaseFunctionsException &&
          ['aborted', 'already-exists'].contains(error.code)) {
        _requests.confirmed(request);
        _pendingKind = null;
      }
      if (mounted) {
        showCompactNotice(
            context, AppLocalizations.of(context)!.reactionFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final view = _view;
    return SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.reactionsTitle,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(l10n.reactionsHint),
                  const SizedBox(height: 16),
                  if (_failed) ...[
                    Text(l10n.reactionFailed),
                    TextButton(
                        onPressed: _listen, child: Text(l10n.retryMediaLabel))
                  ] else if (view == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    if (!view.canReact) Text(l10n.reactionsReadOnly),
                    for (final kind in ['strong', 'source'])
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                              onPressed: !view.canReact || _busy || _cooling
                                  ? null
                                  : () => _react(kind),
                              icon: Icon(
                                  (kind == 'strong' ? view.strong : view.source)
                                      ? Icons.check_circle
                                      : kind == 'strong'
                                          ? Icons.thumb_up_outlined
                                          : Icons.help_outline),
                              label: Text(
                                  '${kind == 'strong' ? l10n.reactionStrong : l10n.reactionSource} · ${kind == 'strong' ? view.strongCount : view.sourceCount}'))),
                    if (_busy) const LinearProgressIndicator(),
                  ],
                ])));
  }
}

class MessageReactionButton extends StatelessWidget {
  const MessageReactionButton(
      {super.key, required this.debateId, required this.messageId});
  final String debateId, messageId;
  @override
  Widget build(BuildContext context) => TextButton.icon(
      style: TextButton.styleFrom(
          foregroundColor: Colors.white70,
          textStyle: const TextStyle(fontSize: 12)),
      icon: const Icon(Icons.add_reaction_outlined, size: 16),
      label: Text(AppLocalizations.of(context)!.reactionsTitle),
      onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) =>
              MessageReactionPanel(debateId: debateId, messageId: messageId)));
}
