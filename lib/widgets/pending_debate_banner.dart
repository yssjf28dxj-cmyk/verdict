import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/pending_debate_service.dart';

/// Wraps child widget and shows a persistent animated banner
/// when a background debate becomes active.
class PendingDebateBanner extends StatefulWidget {
  final Widget child;
  const PendingDebateBanner({super.key, required this.child});

  @override
  State<PendingDebateBanner> createState() => _PendingDebateBannerState();
}

class _PendingDebateBannerState extends State<PendingDebateBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    PendingDebateService.instance.addListener(_onServiceChange);
  }

  void _onServiceChange() {
    if (!mounted) return;
    setState(() {}); // rebuild to show/hide banner

    final debateId = PendingDebateService.instance.activatedDebateId;
    if (debateId != null && !_navigating) {
      _navigating = true;
      // Short delay so user sees the "BATTLE STARTS!" flash
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (!mounted) return;
        PendingDebateService.instance.stopWatching();
        _navigating = false;
        context.go('/debate/$debateId');
      });
    }
  }

  @override
  void dispose() {
    PendingDebateService.instance.removeListener(_onServiceChange);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = PendingDebateService.instance;
    final activatedId = svc.activatedDebateId;
    final isWatching = svc.isWatching;
    final topic = svc.activatedTopic ?? svc.watchedDebateId ?? '';

    return Stack(
      children: [
        widget.child,

        // ── Watching indicator (small pill at top) ──────────────────────
        if (isWatching)
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            right: 16,
            child: _WatchingPill(topic: topic),
          ),

        // ── BATTLE STARTS banner (fullscreen overlay) ───────────────────
        if (activatedId != null)
          Positioned.fill(
            child: _BattleStartsOverlay(pulse: _pulse, topic: topic),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Small pill showing that we are waiting in background
// ────────────────────────────────────────────────────────────────────────────

class _WatchingPill extends StatefulWidget {
  final String topic;
  const _WatchingPill({required this.topic});

  @override
  State<_WatchingPill> createState() => _WatchingPillState();
}

class _WatchingPillState extends State<_WatchingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final id = PendingDebateService.instance.watchedDebateId;
        if (id != null) context.push('/lobby/$id');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F2E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: const Color(0xFFFFB74D).withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.25),
              blurRadius: 14,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _spin,
              child: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFB74D),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Searching…',
              style: TextStyle(
                color: Color(0xFFFFB74D),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Full-screen "BATTLE STARTS!" overlay
// ────────────────────────────────────────────────────────────────────────────

class _BattleStartsOverlay extends StatelessWidget {
  final AnimationController pulse;
  final String topic;
  const _BattleStartsOverlay({required this.pulse, required this.topic});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final glow = pulse.value;
        return Container(
          color: Colors.black.withValues(alpha: 0.80),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lightning bolt
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFD700).withValues(alpha: 0.10 + glow * 0.12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.25 + glow * 0.35),
                        blurRadius: 40 + glow * 30,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bolt,
                    size: 72,
                    color: Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'BATTLE STARTS!',
                  style: TextStyle(
                    color: Color.lerp(
                        const Color(0xFFFFD700), Colors.white, glow * 0.4),
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'ДЕБАТЫ НАЧАТЫ!',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                if (topic.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Text(
                      topic,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                const CircularProgressIndicator(
                  color: Color(0xFFFFD700),
                  strokeWidth: 3,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
