import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../utils/name_utils.dart';

class DebateMessagesList extends StatefulWidget {
  final String debateId;
  final String fighter1Id;
  final bool showWaitingTurn;
  final String waitingText;

  const DebateMessagesList({
    super.key,
    required this.debateId,
    required this.fighter1Id,
    this.showWaitingTurn = false,
    this.waitingText = '',
  });

  @override
  State<DebateMessagesList> createState() => _DebateMessagesListState();
}

class _DebateMessagesListState extends State<DebateMessagesList> {
  final Set<String> _animatedMessageIds = <String>{};

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildAvatar({
    required String senderName,
    required bool isMine,
  }) {
    final safeName = senderName.trim().isEmpty ? '?' : senderName.trim();
    final initial = safeName.substring(0, 1).toUpperCase();
    final color = isMine ? const Color(0xFF3A77FF) : const Color(0xFF8A8F9F);

    return CircleAvatar(
      radius: 12,
      backgroundColor: color.withValues(alpha: 0.22),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _messageBubble({
    required String messageId,
    required Map<String, dynamic> data,
    required bool isMine,
    required AppLocalizations l10n,
  }) {
    final senderName = firstNonEmptyName(
      [data['senderName'], data['sender']],
      fallback: l10n.anonymous,
    );
    final text = (data['text'] ?? '').toString();
    final messageType = (data['messageType'] ?? 'text').toString();
    final mediaUrl = (data['mediaUrl'] ?? '').toString();
    final mediaDuration = (data['mediaDuration'] is num)
        ? (data['mediaDuration'] as num).toInt()
        : 0;
    final createdAt =
        data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;
    final bubbleGradient = isMine
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x663A77FF), Color(0x33224488)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x332A2D35), Color(0x221B1E26)],
          );
    final bubbleBorder =
        isMine ? const Color(0xAA67A2FF) : Colors.white.withValues(alpha: 0.22);

    final bubble = ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMine ? 20 : 6),
        bottomRight: Radius.circular(isMine ? 6 : 20),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: bubbleGradient,
            border: Border.all(color: bubbleBorder, width: 1.1),
            boxShadow: [
              BoxShadow(
                color:
                    isMine ? const Color(0x553A77FF) : const Color(0x3310141C),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Render content based on messageType
              if (messageType == 'voice' && mediaUrl.isNotEmpty)
                _VoiceMessageContent(
                  mediaUrl: mediaUrl,
                  duration: mediaDuration,
                  isMine: isMine,
                )
              else if (messageType == 'image' && mediaUrl.isNotEmpty)
                _ImageMessageContent(
                  mediaUrl: mediaUrl,
                  isMine: isMine,
                )
              else
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.28,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (text.isNotEmpty && messageType != 'text') ...[
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                _formatTime(createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.48),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final rowChild = Row(
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMine) _buildAvatar(senderName: senderName, isMine: isMine),
        if (!isMine) const SizedBox(width: 7),
        Flexible(
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2, right: 2),
                child: Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.3,
                    color: Colors.white.withValues(alpha: 0.54),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              bubble,
            ],
          ),
        ),
        if (isMine) const SizedBox(width: 7),
        if (isMine) _buildAvatar(senderName: senderName, isMine: isMine),
      ],
    );

    // ── Entrance animation (elasticOut slide-up + fade) ──────
    final shouldAnimate = !_animatedMessageIds.contains(messageId);
    if (!shouldAnimate) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: rowChild,
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('msg-enter-$messageId'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.elasticOut,
      onEnd: () {
        if (!mounted) return;
        setState(() => _animatedMessageIds.add(messageId));
      },
      builder: (context, value, child) {
        final clamped = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: clamped,
          child: Transform.translate(
            offset: Offset(0, (1 - clamped) * 36),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: rowChild,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('debates')
          .doc(widget.debateId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context)!;
        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFFA500),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final list = docs.isEmpty
            ? Center(
                child: Text(
                  l10n.noMessagesYet,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
                ),
              )
            : ListView.builder(
                key: const PageStorageKey('messages-list'),
                reverse: true,
                // AlwaysScrollable ensures pull-to-scroll even with few messages
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final senderId = (data['senderId'] ?? '').toString();
                  final isMine =
                      currentUid.isNotEmpty && senderId == currentUid;

                  return _messageBubble(
                    messageId: doc.id,
                    data: data,
                    isMine: isMine,
                    l10n: l10n,
                  );
                },
              );

        if (!widget.showWaitingTurn) return list;

        return Column(
          children: [
            Expanded(child: list),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.waitingText.isNotEmpty
                      ? widget.waitingText
                      : l10n.waitingYourTurn,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── VOICE MESSAGE WIDGET ────────────────────────────────────

class _VoiceMessageContent extends StatefulWidget {
  final String mediaUrl;
  final int duration;
  final bool isMine;

  const _VoiceMessageContent({
    required this.mediaUrl,
    required this.duration,
    required this.isMine,
  });

  @override
  State<_VoiceMessageContent> createState() => _VoiceMessageContentState();
}

class _VoiceMessageContentState extends State<_VoiceMessageContent> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  double _progress = 0; // 0.0 – 1.0
  int _positionSeconds = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _progress = 0;
        _positionSeconds = 0;
      });
    });

    _player.onPositionChanged.listen((pos) {
      if (!mounted || _isDragging) return;
      final totalMs = widget.duration * 1000;
      if (totalMs <= 0) return;
      setState(() {
        _progress = (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
        _positionSeconds = pos.inSeconds;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    HapticFeedback.selectionClick();
    try {
      if (_isPlaying) {
        await _player.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        await _player.play(UrlSource(widget.mediaUrl));
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('[VoicePlayer] Error: $e');
    }
  }

  Future<void> _seekTo(double ratio) async {
    final seekMs = (ratio.clamp(0.0, 1.0) * widget.duration * 1000).round();
    await _player.seek(Duration(milliseconds: seekMs));
    if (mounted) {
      setState(() {
        _progress = ratio.clamp(0.0, 1.0);
        _positionSeconds = (seekMs / 1000).round();
      });
    }
  }

  String _fmt(int seconds) {
    final s = seconds.clamp(0, widget.duration);
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final neonColor =
        widget.isMine ? const Color(0xFF4E8BFF) : const Color(0xFFFFA500);
    final totalLabel = _fmt(widget.duration);
    final posLabel = _fmt(_positionSeconds);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Play / pause button ──
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: neonColor.withValues(alpha: 0.18),
              border: Border.all(color: neonColor.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: neonColor.withValues(alpha: 0.22),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: neonColor,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // ── Seekable waveform + time label ──
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Interactive waveform area
              LayoutBuilder(
                builder: (context, constraints) {
                  const barCount = 24;
                  return GestureDetector(
                    // Tap to seek
                    onTapUp: (details) {
                      final ratio =
                          details.localPosition.dx / constraints.maxWidth;
                      _seekTo(ratio);
                    },
                    // Drag to scrub
                    onHorizontalDragStart: (_) {
                      _isDragging = true;
                    },
                    onHorizontalDragUpdate: (details) {
                      final ratio =
                          details.localPosition.dx / constraints.maxWidth;
                      if (mounted) {
                        setState(() {
                          _progress = ratio.clamp(0.0, 1.0);
                          _positionSeconds =
                              (_progress * widget.duration).round();
                        });
                      }
                    },
                    onHorizontalDragEnd: (_) {
                      _isDragging = false;
                      _seekTo(_progress);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: 28,
                      width: constraints.maxWidth,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(barCount, (i) {
                          final barProgress = i / barCount;
                          final isActive = barProgress <= _progress;
                          // Pseudo-random heights for visual texture
                          final height =
                              7.0 + ((i * 7 + 3) % 15).toDouble();
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 80),
                            width: 3,
                            height: height,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: isActive
                                  ? neonColor
                                  : neonColor.withValues(alpha: 0.18),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color:
                                            neonColor.withValues(alpha: 0.35),
                                        blurRadius: 5,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 4),

              // Live position / total duration
              Row(
                children: [
                  Text(
                    posLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: neonColor.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    ' / $totalLabel',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── IMAGE MESSAGE WIDGET ────────────────────────────────────

class _ImageMessageContent extends StatelessWidget {
  final String mediaUrl;
  final bool isMine;

  const _ImageMessageContent({
    required this.mediaUrl,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final neonColor =
        isMine ? const Color(0xFF4E8BFF) : const Color(0xFFFFA500);

    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: Hero(
        tag: 'img-$mediaUrl',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: neonColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: neonColor.withValues(alpha: 0.18),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.5),
            child: Image.network(
              mediaUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return SizedBox(
                  width: 200,
                  height: 150,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                      color: neonColor,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stack) {
                return Container(
                  width: 200,
                  height: 100,
                  color: Colors.white.withValues(alpha: 0.05),
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: Colors.white24, size: 36),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    final neonColor =
        isMine ? const Color(0xFF4E8BFF) : const Color(0xFFFFA500);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Fullscreen zoomable image
              Center(
                child: Hero(
                  tag: 'img-$mediaUrl',
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          mediaUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white38,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Close button — top right
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 12,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.6),
                      border: Border.all(
                        color: neonColor.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: neonColor.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
