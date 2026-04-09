
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../utils/name_utils.dart';

class DebateMessagesList extends StatefulWidget {
  final String debateId;
  final String fighter1Id;
  final bool showWaitingTurn;
  final String waitingText;
  /// When non-null, shows a local "uploading" placeholder bubble at the
  /// bottom of the chat (index 0 in the reversed list).
  final String? uploadingMediaType;

  const DebateMessagesList({
    super.key,
    required this.debateId,
    required this.fighter1Id,
    this.showWaitingTurn = false,
    this.waitingText = '',
    this.uploadingMediaType,
  });

  @override
  State<DebateMessagesList> createState() => _DebateMessagesListState();
}

class _DebateMessagesListState extends State<DebateMessagesList> {
  // Track which messages have already played their entrance animation.
  final Set<String> _animatedIds = <String>{};

  // ScrollController for programmatic auto-scroll to newest message.
  final ScrollController _scrollController = ScrollController();
  int _lastDocCount = 0;
  bool _autoScrollScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Animates to position 0 (= bottom in a reversed list) when new messages
  // arrive, but ONLY when the user is already near the bottom (< 80px away),
  // so manual scrolling up is never interrupted.
  void _scheduleAutoScrollIfNeeded(int currentCount) {
    if (currentCount <= _lastDocCount) {
      _lastDocCount = currentCount;
      return;
    }
    _lastDocCount = currentCount;
    if (_autoScrollScheduled) return;
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      // In a reversed list offset 0 = bottom. Only scroll if user is close.
      if (pos.pixels < 80) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

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
    required double bottomPadding,
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
    // ── Bubble colour tokens ─────────────────────────────────
    final bubbleColor = isMine ? const Color(0xFFFFD700) : const Color(0xFF2A2A2A);

    final hasImage = messageType == 'image' && mediaUrl.isNotEmpty;

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
        else if (hasImage)
          _ImageMessageContent(mediaUrl: mediaUrl, isMine: isMine)
        else
          Text(
            text,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.28,
              color: isMine ? Colors.black : Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (text.isNotEmpty && messageType != 'text') ...[
          const SizedBox(height: 6),
          Padding(
            padding: hasImage
                ? const EdgeInsets.symmetric(horizontal: 12)
                : EdgeInsets.zero,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isMine ? Colors.black87 : Colors.white70,
              ),
            ),
          ),
        ],
        SizedBox(height: hasImage && text.isEmpty ? 6 : 5),
        // Timestamp — right-aligned micro label
        Padding(
          padding: hasImage
              ? const EdgeInsets.fromLTRB(12, 0, 12, 10)
              : EdgeInsets.zero,
          child: Text(
            _formatTime(createdAt),
            style: TextStyle(
              fontSize: 10,
              color: isMine ? Colors.black54 : Colors.white.withValues(alpha: 0.42),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    final glassBubble = Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: hasImage
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 10, 12, 10),
      clipBehavior: hasImage ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: content,
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
              glassBubble,
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
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: rowContent,
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('msg-anim-$messageId'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      onEnd: () {
        // Use a microtask so we don't trigger setState mid-build.
        Future.microtask(() {
          if (!mounted) return;
          setState(() => _animatedIds.add(messageId));
        });
      },
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 14),
          child: child,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
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

        // Only show spinner on the very first load (no data yet).
        // On reconnects the previous snapshot is reused — no flash.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFFA500)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        _scheduleAutoScrollIfNeeded(docs.length);
        final hasUpload = widget.uploadingMediaType != null;
        final extraCount = hasUpload ? 1 : 0;

        final list = docs.isEmpty && !hasUpload
            ? Center(
                child: Text(
                  l10n.noMessagesYet,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58)),
                ),
              )
            : ListView.builder(
                key: const PageStorageKey<String>('messages-list'),
                controller: _scrollController,
                reverse: true,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                cacheExtent: 400,
                physics: const BouncingScrollPhysics(
                  decelerationRate: ScrollDecelerationRate.fast,
                ),
                padding:
                    const EdgeInsets.fromLTRB(12, 10, 12, 10),
                itemCount: docs.length + extraCount,
                itemBuilder: (_, index) {
                  // Index 0 in reversed list = newest = bottom of screen.
                  if (hasUpload && index == 0) {
                    return _UploadingPlaceholder(
                      mediaType: widget.uploadingMediaType!,
                    );
                  }
                  final docIndex = hasUpload ? index - 1 : index;
                  final doc = docs[docIndex];
                  final data =
                      doc.data() as Map<String, dynamic>? ?? {};
                  final senderId =
                      (data['senderId'] ?? '').toString();
                  final isMine =
                      currentUid.isNotEmpty && senderId == currentUid;
                  
                  double bottomPad = 12.0;
                  if (docIndex > 0) {
                    final nextDoc = docs[docIndex - 1];
                    final nextData = nextDoc.data() as Map<String, dynamic>? ?? {};
                    final nextSenderId = (nextData['senderId'] ?? '').toString();
                    if (nextSenderId == senderId) {
                      bottomPad = 4.0;
                    }
                  }

                  return _messageBubble(
                    messageId: doc.id,
                    data: data,
                    isMine: isMine,
                    l10n: l10n,
                    bottomPadding: bottomPad,
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
// UPLOAD PLACEHOLDER — shown at list bottom while media uploads
// ─────────────────────────────────────────────────────────────

class _UploadingPlaceholder extends StatelessWidget {
  final String mediaType;

  const _UploadingPlaceholder({required this.mediaType});

  @override
  Widget build(BuildContext context) {
    final label = mediaType == 'voice' ? 'Отправка голосового...' : 'Загрузка...';
    final icon = mediaType == 'voice' ? Icons.mic_rounded : Icons.image_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
              color: Color(0xFFFFD700),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
  State<_VoiceMessageContent> createState() => _VoiceMessageContentState();
}

class _VoiceMessageContentState extends State<_VoiceMessageContent>
    with SingleTickerProviderStateMixin {
  late final PlayerController _playerController;
  final ValueNotifier<bool> _isInitializedVN = ValueNotifier(false);
  final ValueNotifier<bool> _isPlayingVN = ValueNotifier(false);
  final ValueNotifier<double> _progressVN = ValueNotifier(0.0);
  final ValueNotifier<int> _positionVN = ValueNotifier(0);

  late final AnimationController _idlePulseCtrl;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _playerController = PlayerController();
    _idlePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _playerController.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      _isPlayingVN.value = state.isPlaying;
      if (state == PlayerState.stopped) {
        _progressVN.value = 0.0;
        _positionVN.value = 0;
      }
    });

    _playerController.onCurrentDurationChanged.listen((dur) {
      if (!mounted || _isDragging) return;
      final totalMs = widget.duration * 1000;
      if (totalMs <= 0) return;
      _progressVN.value = (dur / totalMs).clamp(0.0, 1.0);
      _positionVN.value = (dur / 1000).round();
    });

    _playerController.onCompletion.listen((_) {
      if (!mounted) return;
      _isPlayingVN.value = false;
      _progressVN.value = 0.0;
      _positionVN.value = 0;
    });

    _preparePlayer();
  }

  Future<void> _preparePlayer() async {
    try {
      final dir = await getTemporaryDirectory();
      final hash = widget.mediaUrl.hashCode.toString();
      final file = File('${dir.path}/verdict_audio_$hash.m4a');

      if (!await file.exists()) {
        final resp = await http.get(Uri.parse(widget.mediaUrl));
        if (resp.statusCode == 200) {
          await file.writeAsBytes(resp.bodyBytes);
        } else {
          throw Exception('Failed to download audio');
        }
      }

      await _playerController.preparePlayer(
        path: file.path,
        shouldExtractWaveform: true,
        noOfSamples: 40,
      );
      if (mounted) _isInitializedVN.value = true;
    } catch (e) {
      debugPrint('[VoicePlayer] Init error: $e');
    }
  }

  @override
  void dispose() {
    _idlePulseCtrl.dispose();
    _isPlayingVN.dispose();
    _progressVN.dispose();
    _positionVN.dispose();
    _isInitializedVN.dispose();
    _playerController.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_isInitializedVN.value) return;
    HapticFeedback.selectionClick();
    try {
      if (_isPlayingVN.value) {
        await _playerController.pausePlayer();
      } else {
        await _playerController.startPlayer();
      }
    } catch (e) {
      debugPrint('[VoicePlayer] $e');
    }
  }

  Future<void> _seekTo(double ratio) async {
    if (!_isInitializedVN.value) return;
    final r = ratio.clamp(0.0, 1.0);
    final ms = (r * widget.duration * 1000).round();
    await _playerController.seekTo(ms);
  }

  static String _fmt(int s, int total) {
    final clamped = s.clamp(0, total);
    final mm = (clamped ~/ 60).toString().padLeft(2, '0');
    final ss = (clamped % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final neonColor = widget.isMine ? Colors.black87 : const Color(0xFFFFD700);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                border: Border.all(color: neonColor.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: neonColor.withValues(alpha: 0.22),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: neonColor,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (ctx, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _seekTo(d.localPosition.dx / constraints.maxWidth),
                  onHorizontalDragStart: (_) => _isDragging = true,
                  onHorizontalDragUpdate: (d) {
                    final r = (d.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                    _progressVN.value = r;
                    _positionVN.value = (r * widget.duration).round();
                  },
                  onHorizontalDragEnd: (_) {
                    _isDragging = false;
                    _seekTo(_progressVN.value);
                  },
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isInitializedVN,
                    builder: (_, initialized, __) {
                      if (!initialized) {
                        return SizedBox(
                          height: 28,
                          width: constraints.maxWidth,
                          child: Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: neonColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        );
                      }
                      return AudioFileWaveforms(
                        size: Size(constraints.maxWidth, 28),
                        playerController: _playerController,
                        playerWaveStyle: PlayerWaveStyle(
                          fixedWaveColor: widget.isMine ? Colors.black12 : Colors.white12,
                          liveWaveColor: neonColor,
                          waveCap: StrokeCap.round,
                          spacing: 4,
                          waveThickness: 2.5,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
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
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' / ${_fmt(widget.duration, widget.duration)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: widget.isMine ? Colors.black54 : Colors.white.withValues(alpha: 0.38),
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
        isMine ? Colors.black87 : const Color(0xFFFFD700);

    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: Hero(
        tag: 'img-$mediaUrl',
        child: Image.network(
          mediaUrl,
          fit: BoxFit.cover,
          width: 290, // Fills the max width of the container 
          height: 200, 
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: 290,
              height: 200,
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
            width: 290,
            height: 200,
            color: Colors.black.withValues(alpha: 0.1),
            child: const Center(
              child: Icon(Icons.broken_image_rounded,
                  color: Colors.white24, size: 36),
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    final neonColor =
        isMine ? Colors.black87 : const Color(0xFFFFD700);

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

