import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/home_screen.dart';
import '../screens/create_debate_screen.dart';
import '../screens/debate_room_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/lobby_screen.dart';
import '../screens/profile_history_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/public_profile_screen.dart';
import '../screens/result_screen.dart';
import '../screens/rules_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/world_chat_screen.dart';
import '../screens/welcome_screen.dart';

GoRouter createAppRouter() => GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: false,
  errorBuilder: (context, state) => Scaffold(
    backgroundColor: const Color(0xFF0D1117),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFFD700), size: 48),
          const SizedBox(height: 16),
          const Text(
            'Page not found',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            state.error?.message ?? state.uri.toString(),
            style: const TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            onPressed: () => context.go('/home'),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ),
  ),
  routes: [
    GoRoute(
      path: '/',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/welcome',
      name: 'welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/auth',
      name: 'auth',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/create-debate',
      name: 'create_debate',
      builder: (context, state) => const CreateDebateScreen(),
    ),
    GoRoute(
      path: '/debate/:id',
      name: 'debate_room',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return DebateRoomScreen(debateId: id);
      },
    ),
    GoRoute(
      path: '/result/:id',
      name: 'result',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ResultScreen(debateId: id);
      },
    ),
    GoRoute(
      path: '/lobby/:id',
      name: 'lobby',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return LobbyScreen(debateId: id);
      },
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/public-profile',
      name: 'public_profile',
      builder: (context, state) {
        final data = state.extra as Map<String, dynamic>;
        return PublicProfileScreen(
          uid: data['uid'] as String,
          publicId: data['publicId'] as String,
          name: data['name'] as String,
        );
      },
    ),
    GoRoute(
      path: '/profile-history',
      name: 'profile_history',
      builder: (context, state) {
        final items = state.extra as List<dynamic>;
        return ProfileHistoryScreen(items: items.cast());
      },
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/rules',
      name: 'rules',
      builder: (context, state) => const RulesScreen(),
    ),
    GoRoute(
      path: '/leaderboard',
      name: 'leaderboard',
      builder: (context, state) => const LeaderboardScreen(),
    ),
    GoRoute(
      path: '/world-chat',
      name: 'world_chat',
      builder: (context, state) => const WorldChatScreen(),
    ),
  ],
);
