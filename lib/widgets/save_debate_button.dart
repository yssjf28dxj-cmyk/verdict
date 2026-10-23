import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/saved_debates_service.dart';
import '../utils/compact_notice.dart';

class SaveDebateButton extends StatefulWidget {
  const SaveDebateButton(
      {super.key, required this.debateId, this.read, this.write});
  final String debateId;
  final Future<bool> Function(String)? read;
  final Future<void> Function(String, bool)? write;
  @override
  State<SaveDebateButton> createState() => _SaveDebateButtonState();
}

class _SaveDebateButtonState extends State<SaveDebateButton> {
  SavedDebatesService? _service;
  bool? _saved;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.read == null) _service ??= SavedDebatesService();
      final saved = await (widget.read ?? _service!.contains)(widget.debateId);
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      if (mounted) {
        showCompactNotice(
            context, AppLocalizations.of(context)!.savedDebatesError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_saved == null) {
      await _load();
      return;
    }
    try {
      if (widget.write == null) _service ??= SavedDebatesService();
      final next = !_saved!;
      await (widget.write ?? _service!.setSaved)(widget.debateId, next);
      if (mounted) setState(() => _saved = next);
    } catch (_) {
      if (mounted) {
        showCompactNotice(
            context, AppLocalizations.of(context)!.savedDebatesError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
        onPressed: _busy ? null : _toggle,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(_saved == true ? Icons.bookmark : Icons.bookmark_border),
        label: Text(_saved == null
            ? l10n.retryMediaLabel
            : _saved!
                ? l10n.removeSavedDebate
                : l10n.saveDebate));
  }
}
