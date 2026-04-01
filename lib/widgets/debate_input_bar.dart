import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DebateInputBar — fully self-contained input bar for the Debate Room.
//
// Three visual states:
//   • Normal  — text field + mic (hold) + gallery + send
//   • Recording — pulsing dot, live timer, animated waveform, cancel/send
//   • Uploading — progress spinner with label
//
// Architecture:
//   • _NormalInputBar is StatefulWidget — owns its own isTyping ValueNotifier
//     so the parent screen does NOT rebuild on every keystroke.
//   • _RecordingBar uses Stream.periodic for the timer (no setState in parent).
//   • All leaf widgets use const constructors where possible.
// ─────────────────────────────────────────────────────────────────────────────

class DebateInputBar extends StatelessWidget {
  final bool isMyTurn;
  final bool isSendingMessage;
  final bool isUploading;
  final bool isRecording;
  final bool isRoundActive;
  final bool isYielding;
  final DateTime? recordingStartTime;
  final TextEditingController textController;
  final VoidCallback onSend;
  final void Function(LongPressStartDetails) onMicLongPressStart;
  final void Function(LongPressEndDetails) onMicLongPressEnd;
  final VoidCallback onPickImage;
  final VoidCallback onCancelRecording;
  final VoidCallback onSendRecording;
  /// Called when the user confirms yielding (either Flow A or Flow B).
  /// Null when yield is not available (not speaker's turn, round inactive).
  final VoidCallback? onYield;

  const DebateInputBar({
    super.key,
    required this.isMyTurn,
    required this.isSendingMessage,
    required this.isUploading,
    required this.isRecording,
    required this.isRoundActive,
    required this.isYielding,
    required this.recordingStartTime,
    required this.textController,
    required this.onSend,
    required this.onMicLongPressStart,
    required this.onMicLongPressEnd,
    required this.onPickImage,
    required this.onCancelRecording,
    required this.onSendRecording,
    this.onYield,
  });

  bool get _yieldAvailable => isMyTurn && isRoundActive && !isYielding;

  @override
  Widget build(BuildContext context) {
    if (isRecording) {
      return _RecordingBar(
        recordingStartTime: recordingStartTime,
        onCancel: onCancelRecording,
        onSend: onSendRecording,
      );
    }
    // Uploading no longer shows a full-width blocking bar.
    // The normal bar stays visible with inputs disabled and an inline spinner
    // replacing the send button — yield remains accessible (Policy B).
    return _NormalInputBar(
      isMyTurn: isMyTurn,
      isSending: isSendingMessage,
      isUploading: isUploading,
      yieldAvailable: _yieldAvailable,
      textController: textController,
      onSend: onSend,
      onMicLongPressStart: onMicLongPressStart,
      onMicLongPressEnd: onMicLongPressEnd,
      onPickImage: onPickImage,
      onYield: onYield,
    );
  }
}

// ─── NORMAL STATE ────────────────────────────────────────────

class _NormalInputBar extends StatefulWidget {
  final bool isMyTurn;
  final bool isSending;
  final bool isUploading;
  final bool yieldAvailable;
  final TextEditingController textController;
  final VoidCallback onSend;
  final void Function(LongPressStartDetails) onMicLongPressStart;
  final void Function(LongPressEndDetails) onMicLongPressEnd;
  final VoidCallback onPickImage;
  final VoidCallback? onYield;

  const _NormalInputBar({
    required this.isMyTurn,
    required this.isSending,
    required this.isUploading,
    required this.yieldAvailable,
    required this.textController,
    required this.onSend,
    required this.onMicLongPressStart,
    required this.onMicLongPressEnd,
    required this.onPickImage,
    this.onYield,
  });

  @override
  State<_NormalInputBar> createState() => _NormalInputBarState();
}

class _NormalInputBarState extends State<_NormalInputBar> {
  late final ValueNotifier<bool> _isTypingNotifier;

  void _onTextChanged() {
    _isTypingNotifier.value =
        widget.textController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _isTypingNotifier = ValueNotifier(
      widget.textController.text.trim().isNotEmpty,
    );
    widget.textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    _isTypingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Uploading locks gallery/mic/send but not yield (Policy B).
    final canAct = widget.isMyTurn && !widget.isSending && !widget.isUploading;

    return Row(
      children: [
        // ── Gallery button ──
        _MediaButton(
          icon: Icons.photo_outlined,
          onTap: canAct ? widget.onPickImage : null,
          enabled: canAct,
        ),
        const SizedBox(width: 6),

        // ── Text field with animated typing border ──
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: _isTypingNotifier,
            builder: (_, isTyping, child) => AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF141C2F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isTyping
                      ? const Color(0xFF4E8BFF)
                      : Colors.white.withValues(alpha: 0.14),
                  width: isTyping ? 1.4 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isTyping
                        ? const Color(0x664E8BFF)
                        : const Color(0x18000000),
                    blurRadius: isTyping ? 18 : 10,
                    spreadRadius: isTyping ? 1 : 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
            // TextField is NOT rebuilt when isTyping changes —
            // only the AnimatedContainer decoration updates.
            child: TextField(
              controller: widget.textController,
              enabled: widget.isMyTurn,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canAct) widget.onSend();
              },
              decoration: InputDecoration(
                hintText: widget.isMyTurn
                    ? _safeHint(l10n)
                    : l10n.waitForOpponentTurn,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
              ),
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // ── Mic button (hold to record) ──
        GestureDetector(
          onLongPressStart:
              canAct ? widget.onMicLongPressStart : null,
          onLongPressEnd:
              canAct ? widget.onMicLongPressEnd : null,
          child: _MediaButton(
            icon: Icons.mic_rounded,
            enabled: canAct,
          ),
        ),
        const SizedBox(width: 6),

        // ── Yield button (active speaker only) ──
        if (widget.yieldAvailable) ...[
          _YieldButton(onTap: widget.onYield),
          const SizedBox(width: 6),
        ],

        // ── Send / Upload spinner ──
        if (widget.isUploading)
          const SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFFFFA500),
                ),
              ),
            ),
          )
        else
          _SendButton(
            enabled: canAct,
            onTap: canAct ? widget.onSend : null,
          ),
      ],
    );
  }

  String _safeHint(AppLocalizations l10n) {
    final raw = l10n.messageHint.trim();
    if (raw.isEmpty || raw.toUpperCase() == 'NOT_FOUND') {
      return 'Write a message...';
    }
    return raw;
  }
}

// ─── RECORDING STATE ─────────────────────────────────────────

class _RecordingBar extends StatelessWidget {
  final DateTime? recordingStartTime;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _RecordingBar({
    required this.recordingStartTime,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFFF4B4B).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4B4B).withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing dot
          const _PulsingDot(),
          const SizedBox(width: 12),

          // Live timer
          StreamBuilder<void>(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (_, __) {
              final elapsed = recordingStartTime != null
                  ? DateTime.now()
                      .difference(recordingStartTime!)
                      .inSeconds
                  : 0;
              final mm = (elapsed ~/ 60).toString().padLeft(2, '0');
              final ss = (elapsed % 60).toString().padLeft(2, '0');
              return Text(
                '$mm:$ss',
                style: const TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              );
            },
          ),
          const SizedBox(width: 12),

          // Animated waveform
          const Expanded(child: _RecordingWaveform()),
          const SizedBox(width: 12),

          // Cancel
          IconButton(
            icon: const Icon(Icons.close,
                color: Colors.white54, size: 20),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          // Send
          IconButton(
            icon: const Icon(Icons.send_rounded,
                color: Color(0xFFFF4B4B), size: 22),
            onPressed: onSend,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
            const Color(0xFFFF4B4B).withValues(alpha: 0.3),
            const Color(0xFFFF4B4B),
            _anim.value,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4B4B)
                  .withValues(alpha: _anim.value * 0.5),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingWaveform extends StatefulWidget {
  const _RecordingWaveform();

  @override
  State<_RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<_RecordingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barCount = 16;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            // Each bar animates with a phase offset for wave effect
            final phase = (i / barCount) * 3.14159;
            final rawVal = (_ctrl.value * 3.14159 + phase);
            final barH = 4.0 + (rawVal % 3.14159) / 3.14159 * 16.0;
            return Container(
              width: 2.5,
              height: barH,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4B4B).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── SHARED LEAF WIDGETS ─────────────────────────────────────

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  const _MediaButton({
    required this.icon,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      width: 42,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Opacity(
          opacity: enabled ? 0.72 : 0.30,
          child: InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: onTap,
            child: Center(
              child: Icon(icon, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _YieldButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _YieldButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      width: 42,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Tooltip(
          message: 'Уступить слово',
          child: InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: onTap,
            child: Center(
              child: Icon(
                Icons.skip_next_rounded,
                size: 22,
                color: const Color(0xFFFFA500).withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _SendButton({required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      width: 42,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.40,
          child: InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: onTap,
            child: Center(
              child: Icon(
                Icons.send_rounded,
                size: 20,
                color: enabled
                    ? const Color(0xFFFFA500)
                    : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
