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
  // Track which messages have already played their entrance animation.
  final Set<String> _animatedIds = <String>{};

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildAvatar({required String name, required bool isMine}) {
    final safe = name.trim().isEmpty ? '?' : name.trim();
    final initial = safe.substring(0, 1).toUpperCase();
    final color =
        isMine ? const Color(0xFF3A77FF) : const Color(0xFF8A8F9F);
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
    final createdAt = data['createdAt'] is Timestamp
        ? data['createdAt'] as Timestamp
        : null;

    // ── Bubble colour tokens ─────────────────────────────────
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
    final bubbleBorderColor = isMine
        ? const Color(0xAA67A2FF)
        : Colors.white.withValues(alpha: 0.22);
    // Tail colours — approximate the bubble gradient endpoint
    final tailFill =
        isMine ? const Color(0x44224488) : const Color(0x22222830);
    final tailStroke = isMine
        ? const Color(0x8867A2FF)
        : Colors.white.withValues(alpha: 0.20);

    // ── Inner content ────────────────────────────────────────
    final content = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (messageType == 'voice' && mediaUrl.isNotEmpty)
          _VoiceMessageContent(
            mediaUrl: mediaUrl,
            duration: mediaDuration,
            isMine: isMine,
          )
        else if (messageType == 'image' && mediaUrl.isNotEmpty)
          _ImageMessageContent(mediaUrl: mediaUrl, isMine: isMine)
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
        const SizedBox(height: 5),
        // Timestamp — right-aligned micro label
        Text(
          _formatTime(createdAt),
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.42),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    // ── Glass bubble ─────────────────────────────────────────
    final glassBubble = ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMine ? 20 : 4),
        bottomRight: Radius.circular(isMine ? 4 : 20),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            gradient: bubbleGradient,
            border: Border.all(color: bubbleBorderColor, width: 1.1),
            boxShadow: [
              BoxShadow(
                color: isMine
                    ? const Color(0x553A77FF)
                    : const Color(0x3310141C),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );

    // ── Bubble + tail ────────────────────────────────────────
    // The tail is a small triangle that appears outside the ClipRRect,
    // positioned at the sharp corner (bottom-right for mine, bottom-left
    // for other). This gives the classic chat-bubble arrow effect.
    final bubbleWithTail = Stack(
      clipBehavior: Clip.none,
      children: [
        glassBubble,
        Positioned(
          bottom: 0,
          right: isMine ? 0 : null,
          left: isMine ? null : 0,
          child: Transform.translate(
            offset: Offset(isMine ? 7.0 : -7.0, 0),
            child: CustomPaint(
              painter: _BubbleTailPainter(
                isMine: isMine,
                fillColor: tailFill,
                strokeColor: tailStroke,
              ),
              size: const Size(8, 12),
            ),
          ),
        ),
      ],
    );

    // ── Row layout: avatar + [name + bubble] ─────────────────
    final rowContent = Row(
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMine) ...[
          _buildAvatar(name: senderName, isMine: isMine),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sender name — micro label above bubble
              Padding(
                padding:
                    const EdgeInsets.only(bottom: 3, left: 2, right: 2),
                child: Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.3,
                    color: Colors.white.withValues(alpha: 0.52),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              bubbleWithTail,
            ],
          ),
        ),
        if (isMine) ...[
          const SizedBox(width: 7),
          _buildAvatar(name: senderName, isMine: isMine),
        ],
      ],
    );

    // ── Entrance animation (elasticOut slide-up + fade) ──────
    final alreadyAnimated = _animatedIds.contains(messageId);
    if (alreadyAnimated) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: rowContent,
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('msg-anim-$messageId'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.elasticOut,
      onEnd: () {
        if (!mounted) return;
        setState(() => _animatedIds.add(messageId));
      },
      builder: (_, value, child) {
        final clamped = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: clamped,
          child: Transform.translate(
            offset: Offset(0, (1 - clamped) * 34),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: rowContent,
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
        final currentUid =
            FirebaseAuth.instance.currentUser?.uid ?? '';

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFFA500)),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final list = docs.isEmpty
            ? Center(
                child: Text(
                  l10n.noMessagesYet,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58)),
                ),
              )
            : ListView.builder(
                key: const PageStorageKey<String>('messages-list'),
                reverse: true,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding:
                    const EdgeInsets.fromLTRB(12, 10, 12, 10),
                itemCount: docs.length,
                itemBuilder: (_, index) {
                  final doc = docs[index];
                  final data =
                      doc.data() as Map<String, dynamic>? ?? {};
                  final senderId =
                      (data['senderId'] ?? '').toString();
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
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 12),
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

// ─────────────────────────────────────────────────────────────
// VOICE MESSAGE PLAYER
//
// Architecture: zero setState calls during playback.
// All reactive state lives in ValueNotifiers:
//   _isPlayingVN  — drives play/pause icon
//   _progressVN   — drives waveform bar active-state
//   _positionVN   — drives live time label
//
// Drag scrubbing updates VNs directly; seek() is called on drag-end.
// ─────────────────────────────────────────────────────────────

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
  State<_VoiceMessageContent> createState() =>
      _VoiceMessageContentState();
}

class _VoiceMessageContentState extends State<_VoiceMessageContent> {
  final AudioPlayer _player = AudioPlayer();

  // ValueNotifiers — no setState needed during playback
  final ValueNotifier<bool> _isPlayingVN = ValueNotifier(false);
  final ValueNotifier<double> _progressVN = ValueNotifier(0.0);
  final ValueNotifier<int> _positionVN = ValueNotifier(0);

  bool _isDragging = false;

  @override
  void initState() {
    super.initState();

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      _isPlayingVN.value = false;
      _progressVN.value = 0.0;
      _positionVN.value = 0;
    });

    _player.onPositionChanged.listen((pos) {
      if (!mounted || _isDragging) return;
      final totalMs = widget.duration * 1000;
      if (totalMs <= 0) return;
      _progressVN.value =
          (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
      _positionVN.value = pos.inSeconds;
    });
  }

  @override
  void dispose() {
    _isPlayingVN.dispose();
    _progressVN.dispose();
    _positionVN.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    HapticFeedback.selectionClick();
    try {
      if (_isPlayingVN.value) {
        await _player.pause();
        _isPlayingVN.value = false;
      } else {
        await _player.play(UrlSource(widget.mediaUrl));
        _isPlayingVN.value = true;
      }
    } catch (e) {
      debugPrint('[VoicePlayer] $e');
    }
  }

  Future<void> _seekTo(double ratio) async {
    final r = ratio.clamp(0.0, 1.0);
    final ms = (r * widget.duration * 1000).round();
    _progressVN.value = r;
    _positionVN.value = (ms / 1000).round();
    await _player.seek(Duration(milliseconds: ms));
  }

  static String _fmt(int s, int total) {
    final clamped = s.clamp(0, total);
    final mm = (clamped ~/ 60).toString().padLeft(2, '0');
    final ss = (clamped % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final neonColor = widget.isMine
        ? const Color(0xFF4E8BFF)
        : const Color(0xFFFFA500);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Play / Pause button ───────────────────────────────
        // Rebuilt ONLY when _isPlayingVN changes (rare).
        ValueListenableBuilder<bool>(
          valueListenable: _isPlayingVN,
          builder: (_, isPlaying, __) => GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: neonColor.withValues(alpha: 0.16),
                border: Border.all(
                    color: neonColor.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: neonColor.withValues(alpha: 0.22),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: neonColor,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // ── Seekable waveform + time label ───────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Waveform: GestureDetector wraps LayoutBuilder so we
              // know maxWidth for seek ratio calculation.
              LayoutBuilder(
                builder: (ctx, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Tap → instant seek
                  onTapUp: (d) => _seekTo(
                      d.localPosition.dx / constraints.maxWidth),
                  // Drag → live scrub
                  onHorizontalDragStart: (_) => _isDragging = true,
                  onHorizontalDragUpdate: (d) {
                    final r = (d.localPosition.dx /
                            constraints.maxWidth)
                        .clamp(0.0, 1.0);
                    _progressVN.value = r;
                    _positionVN.value =
                        (r * widget.duration).round();
                  },
                  onHorizontalDragEnd: (_) {
                    _isDragging = false;
                    _seekTo(_progressVN.value);
                  },
                  // Waveform bars rebuilt ONLY when _progressVN changes.
                  child: ValueListenableBuilder<double>(
                    valueListenable: _progressVN,
                    builder: (_, progress, __) => SizedBox(
                      height: 28,
                      width: constraints.maxWidth,
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: List.generate(24, (i) {
                          final active = (i / 24) <= progress;
                          final h = 6.0 +
                              ((i * 7 + 3) % 16).toDouble();
                          return AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 60),
                            width: 3,
                            height: h,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(2),
                              color: active
                                  ? neonColor
                                  : neonColor.withValues(
                                      alpha: 0.16),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: neonColor.withValues(
                                            alpha: 0.35),
                                        blurRadius: 5,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Time: rebuilt ONLY when _positionVN changes.
              ValueListenableBuilder<int>(
                valueListenable: _positionVN,
                builder: (_, pos, __) => Row(
                  children: [
                    Text(
                      _fmt(pos, widget.duration),
                      style: TextStyle(
                        fontSize: 10,
                        color: neonColor.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ],
                      ),
                    ),
                    Text(
                      ' / ${_fmt(widget.duration, widget.duration)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.38),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// IMAGE MESSAGE — premium rounded thumbnail + fullscreen viewer
// ─────────────────────────────────────────────────────────────

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
          constraints:
              const BoxConstraints(maxWidth: 240, maxHeight: 240),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: neonColor.withValues(alpha: 0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: neonColor.withValues(alpha: 0.18),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14.5),
            child: Image.network(
              mediaUrl,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
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
              errorBuilder: (_, __, ___) => Container(
                width: 200,
                height: 100,
                color: Colors.white.withValues(alpha: 0.05),
                child: const Center(
                  child: Icon(Icons.broken_image_rounded,
                      color: Colors.white24, size: 36),
                ),
              ),
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
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity:
            CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(
            CurvedAnimation(
                parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, __) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
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
            // Close button
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BUBBLE TAIL PAINTER
//
// Draws a small triangle that extends from the sharp corner of
// the glass bubble, creating the classic chat-message arrow.
// Positioned outside the ClipRRect via Stack(clipBehavior: none).
// ─────────────────────────────────────────────────────────────

class _BubbleTailPainter extends CustomPainter {
  final bool isMine;
  final Color fillColor;
  final Color strokeColor;

  const _BubbleTailPainter({
    required this.isMine,
    required this.fillColor,
    required this.strokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round;

    final path = isMine
        ? (Path()
          ..moveTo(0, 0) // top-left  (touching the bubble corner)
          ..lineTo(size.width, 0) // top-right (tip)
          ..lineTo(0, size.height) // bottom-left
          ..close())
        : (Path()
          ..moveTo(size.width, 0) // top-right (touching bubble corner)
          ..lineTo(0, 0) // top-left  (tip)
          ..lineTo(size.width, size.height) // bottom-right
          ..close());

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) =>
      old.isMine != isMine || old.fillColor != fillColor;
}
