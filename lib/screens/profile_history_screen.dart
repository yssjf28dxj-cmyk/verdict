import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../firebase_session.dart';
import '../l10n/app_localizations.dart';

import '../models/debate_history_item.dart';
import '../services/debate_history_service.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';

class ProfileHistoryScreen extends StatefulWidget {
  const ProfileHistoryScreen({
    super.key,
    this.loadPage,
    this.hasMore,
  });

  final Future<List<DebateHistoryItem>> Function(bool reset)? loadPage;
  final bool Function()? hasMore;

  @override
  State<ProfileHistoryScreen> createState() => _ProfileHistoryScreenState();
}

class _ProfileHistoryScreenState extends State<ProfileHistoryScreen> {
  String _filter = 'all';
  final _items = <DebateHistoryItem>[];
  DebateHistoryService? _service;
  bool _busy = true, _failed = false;
  bool get _hasMore => widget.hasMore?.call() ?? _service!.hasMore;
  @override
  void initState() {
    super.initState();
    if (widget.loadPage == null) _service = DebateHistoryService();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _busy = true;
      _failed = false;
      if (reset) _items.clear();
    });
    try {
      final rows = await (widget.loadPage?.call(reset) ??
          _service!.nextPage(reset: reset));
      if (mounted) {
        setState(() {
          final merged = {
            for (final row in _items) row.debateId: row,
            for (final row in rows) row.debateId: row
          };
          _items
            ..clear()
            ..addAll(merged.values);
          _items.sort((a, b) => (b.createdAt ?? DateTime(1970))
              .compareTo(a.createdAt ?? DateTime(1970)));
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _outcomeColor(String outcome) {
    switch (outcome) {
      case 'WIN':
        return const Color(0xFF4CAF50);
      case 'LOSS':
        return const Color(0xFFFF6B6B);
      case 'DRAW':
        return const Color(0xFFFFB74D);
      default:
        return Colors.white70;
    }
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) return '--';
    final local = createdAt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  List<DebateHistoryItem> _filteredItems() {
    switch (_filter) {
      case 'live':
        return _items
            .where((e) => e.status == 'live' || e.status == 'active')
            .toList();
      case 'finished':
        return _items.where((e) => e.status == 'finished').toList();
      case 'win':
        return _items.where((e) => e.outcomeLabel == 'WIN').toList();
      case 'loss':
        return _items.where((e) => e.outcomeLabel == 'LOSS').toList();
      case 'draw':
        return _items.where((e) => e.outcomeLabel == 'DRAW').toList();
      default:
        return _items;
    }
  }

  Widget _filterChip(String key, String label) {
    return ChoiceChip(
      selected: _filter == key,
      onSelected: (_) {
        setState(() {
          _filter = key;
        });
      },
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: VerdictStyle.bg,
        foregroundColor: Colors.white,
        title: Text(l10n.debateHistoryTitle),
        actions: [
          IconButton(
              tooltip: l10n.refreshDebates,
              onPressed: _busy ? null : () => _load(reset: true),
              icon: const Icon(Icons.refresh)),
          if (testProfilesEnabled)
            IconButton(
                tooltip: AppLocalizations.of(context)!.savedDebatesTitle,
                onPressed: () => context.push('/saved-debates'),
                icon: const Icon(Icons.bookmarks_outlined))
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip('all', l10n.allDebates),
                    _filterChip('live', l10n.liveStatus),
                    _filterChip('finished', l10n.finishedStatus),
                    _filterChip('win', l10n.wins),
                    _filterChip('loss', l10n.losses),
                    _filterChip('draw', l10n.draws),
                  ],
                ),
              ),
              if (_failed)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(l10n.debateHistoryError)),
              if (_busy) const LinearProgressIndicator(),
              if (!_busy && (_failed || _hasMore))
                TextButton(
                    onPressed: () => _load(),
                    child: Text(
                        _failed ? l10n.retryMediaLabel : l10n.moreDebates)),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.historyEmpty,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              onTap: () =>
                                  context.push('/lobby/${item.debateId}'),
                              child: GlassCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.topic.isEmpty
                                          ? l10n.unknownTopic
                                          : item.topic,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'vs ${item.opponentLabel}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Text(
                                          item.outcomeLabel,
                                          style: TextStyle(
                                            color: _outcomeColor(
                                                item.outcomeLabel),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          item.status.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          _formatCreatedAt(item.createdAt),
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
