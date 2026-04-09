import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../utils/style_utils.dart';

class GlobalBottomNav extends StatelessWidget {
  final int currentIndex;

  const GlobalBottomNav({super.key, required this.currentIndex});

  String _safeLocalizedText(String raw, String fallback) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.toUpperCase() == 'NOT_FOUND') {
      return fallback;
    }
    return normalized;
  }

  void _onNavTap(BuildContext context, int idx) {
    if (idx == currentIndex) return;

    String targetRoute = '';
    if (idx == 0) {
      targetRoute = '/home';
    } else if (idx == 1) {
      targetRoute = '/leaderboard';
    } else if (idx == 2) {
      targetRoute = '/world-chat';
    } else if (idx == 3) {
      targetRoute = '/profile';
    }
    
    if (targetRoute.isNotEmpty) {
      context.push(targetRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (idx) => _onNavTap(context, idx),
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.home),
          label: l10n != null ? _safeLocalizedText(l10n.mainTab, 'Home') : 'Home',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.leaderboard),
          label: 'Leaderboard',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.forum_outlined),
          label: l10n != null ? _safeLocalizedText(l10n.worldChatTab, 'Chat') : 'Chat',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.person),
          label: l10n != null ? _safeLocalizedText(l10n.profileTab, 'Profile') : 'Profile',
        ),
      ],
      selectedItemColor: VerdictStyle.accentGold,
      unselectedItemColor: Colors.grey,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      backgroundColor: const Color(0xFF0E1320),
    );
  }
}
