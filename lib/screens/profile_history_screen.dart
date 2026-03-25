import 'package:flutter/material.dart';

import '../models/debate_history_item.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';

class ProfileHistoryScreen extends StatefulWidget {
  const ProfileHistoryScreen({
    super.key,
    required this.items,
  });

  final List<DebateHistoryItem> items;

  @override
  State<ProfileHistoryScreen> createState() => _ProfileHistoryScreenState();
}

class _ProfileHistoryScreenState extends State<ProfileHistoryScreen> {
  String _filter = 'all';

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
        return widget.items
            .where((e) => e.status == 'live' || e.status == 'active')
            .toList();
      case 'finished':
        return widget.items.where((e) => e.status == 'finished').toList();
      case 'win':
        return widget.items.where((e) => e.outcomeLabel == 'WIN').toList();
      case 'loss':
        return widget.items.where((e) => e.outcomeLabel == 'LOSS').toList();
      case 'draw':
        return widget.items.where((e) => e.outcomeLabel == 'DRAW').toList();
      default:
        return widget.items;
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

    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: VerdictStyle.bg,
        foregroundColor: Colors.white,
        title: const Text('Debate History'),
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
                    _filterChip('all', 'All'),
                    _filterChip('live', 'Live'),
                    _filterChip('finished', 'Finished'),
                    _filterChip('win', 'Wins'),
                    _filterChip('loss', 'Losses'),
                    _filterChip('draw', 'Draws'),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'No debates for selected filter',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.topic,
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
                                  Row(
                                    children: [
                                      Text(
                                        item.outcomeLabel,
                                        style: TextStyle(
                                          color:
                                              _outcomeColor(item.outcomeLabel),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        item.status.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
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
