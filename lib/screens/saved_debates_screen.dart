import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/saved_debates_service.dart';
import '../utils/compact_notice.dart';

class SavedDebatesScreen extends StatefulWidget {
  const SavedDebatesScreen({super.key});
  @override
  State<SavedDebatesScreen> createState() => _SavedDebatesScreenState();
}

class _SavedDebatesScreenState extends State<SavedDebatesScreen> {
  late final SavedDebatesService _service;
  final _rows = <SavedDebate>[];
  final _removing = <String>{};
  bool _busy = true, _failed = false;
  @override
  void initState() {
    super.initState();
    _service = SavedDebatesService();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_removing.isNotEmpty) return;
    setState(() {
      _busy = true;
      _failed = false;
      if (reset) _rows.clear();
    });
    try {
      final rows = await _service.nextPage(reset: reset);
      if (mounted) {
        setState(() {
          final merged = {
            for (final row in _rows) row.id: row,
            for (final row in rows) row.id: row
          };
          _rows
            ..clear()
            ..addAll(merged.values);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String id) async {
    if (_busy || !_removing.add(id)) return;
    setState(() {});
    try {
      await _service.setSaved(id, false);
      if (mounted) setState(() => _rows.removeWhere((row) => row.id == id));
    } catch (_) {
      if (mounted) {
        showCompactNotice(
            context, AppLocalizations.of(context)!.savedDebatesError);
      }
    } finally {
      if (mounted) setState(() => _removing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
        appBar: AppBar(title: Text(l10n.savedDebatesTitle), actions: [
          IconButton(
              tooltip: l10n.refreshDebates,
              onPressed: _busy || _removing.isNotEmpty
                  ? null
                  : () => _load(reset: true),
              icon: const Icon(Icons.refresh))
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (!_busy && !_failed && _rows.isEmpty)
            Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.savedDebatesEmpty)),
          for (final row in _rows)
            Card(
                child: ListTile(
                    title: Text(row.topic ?? l10n.savedDebateUnavailable,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    onTap: row.topic == null
                        ? null
                        : () => context.push('/lobby/${row.id}'),
                    trailing: IconButton(
                        tooltip: l10n.removeSavedDebate,
                        onPressed: _busy || _removing.contains(row.id)
                            ? null
                            : () => _remove(row.id),
                        icon: const Icon(Icons.bookmark_remove_outlined)))),
          if (_failed)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.savedDebatesError)),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_failed || _service.hasMore)
            TextButton(
                onPressed: _removing.isNotEmpty ? null : () => _load(),
                child: Text(_failed ? l10n.retryMediaLabel : l10n.moreDebates)),
        ]));
  }
}
