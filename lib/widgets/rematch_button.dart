import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/rematch_service.dart';
import '../utils/compact_notice.dart';
import '../utils/pending_message_request.dart';

typedef RequestRematch = Future<String> Function(
    String sourceId, String requestId);

class RematchButton extends StatefulWidget {
  const RematchButton(
      {super.key,
      required this.sourceId,
      required this.topic,
      required this.opponentName,
      required this.durationSeconds,
      required this.rounds,
      this.request});
  final String sourceId;
  final String topic;
  final String opponentName;
  final int durationSeconds;
  final int rounds;
  final RequestRematch? request;
  @override
  State<RematchButton> createState() => _RematchButtonState();
}

class _RematchButtonState extends State<RematchButton> {
  final _requests = PendingMessageRequest();
  bool _confirming = false;
  bool _sending = false;

  Future<void> _offer() async {
    if (_confirming || _sending) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _confirming = true);
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: Text(l10n.rematchOffer),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(widget.opponentName,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 12),
                        Text(widget.topic,
                            maxLines: 4, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 12),
                        Text(
                            '${l10n.roundTimeLabel}: ${widget.durationSeconds ~/ 60}:${(widget.durationSeconds % 60).toString().padLeft(2, '0')}'),
                        Text('${l10n.roundsLabel}: ${widget.rounds}'),
                        const SizedBox(height: 12),
                        Text(l10n.rematchHint),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: Text(MaterialLocalizations.of(dialogContext)
                            .cancelButtonLabel)),
                    FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(l10n.rematchConfirm)),
                  ]));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    final request = _requests.forText(widget.sourceId);
    try {
      final id = await (widget.request ?? RematchService().request)(
          widget.sourceId, request.id);
      _requests.confirmed(request);
      if (mounted) context.push('/lobby/$id');
    } catch (error) {
      final cancelled = error is FirebaseFunctionsException &&
          error.details is Map &&
          (error.details as Map)['reason'] == 'REMATCH_PREVIOUS_CANCELLED';
      if (cancelled) _requests.confirmed(request);
      if (mounted) {
        showCompactNotice(
            context, cancelled ? l10n.rematchCancelled : l10n.rematchFailed);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: _confirming || _sending ? null : _offer,
      icon: _sending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.replay_rounded),
      label: Text(AppLocalizations.of(context)!.rematchOffer));
}
