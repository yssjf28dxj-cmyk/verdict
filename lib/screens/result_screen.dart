import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/name_utils.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import 'home_screen.dart';

class ResultScreen extends StatelessWidget {
  final String debateId;

  const ResultScreen({super.key, required this.debateId});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1320), // Фирменный темный фон
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1320),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // Убираем стрелку "назад"
        title: Text(
          l10n.appTitle,
          style: const TextStyle(
            color: Color(0xFFFFA500),
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('debates')
                .doc(debateId)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFA500)));
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Center(
                    child: Text(l10n.battleDataNotFound,
                        style: const TextStyle(color: Colors.white)));
              }

              final rawData = snapshot.data!.data();
              if (rawData == null) {
                return Center(
                    child: Text(l10n.battleDataNotFound,
                        style: const TextStyle(color: Colors.white)));
              }
              final data = rawData as Map<String, dynamic>;
              final topic = firstNonEmptyName(
                [data['topic']],
                fallback: l10n.unknownTopic,
              );
              final fighter1Name = firstNonEmptyName(
                [data['fighter1Name'], data['fighter1']],
                fallback: l10n.fighterOne,
              );
              final fighter2Name = firstNonEmptyName(
                [data['fighter2Name'], data['fighter2']],
                fallback: l10n.fighterTwo,
              );
              final votes1 = data['votes1'] ?? 0;
              final votes2 = data['votes2'] ?? 0;

              String winnerName = l10n.draw;
              Color winnerColor = Colors.grey;
              if (votes1 > votes2) {
                winnerName = '${l10n.victoryPrefix}: $fighter1Name';
                winnerColor = VerdictStyle.fighterBlue;
              } else if (votes2 > votes1) {
                winnerName = '${l10n.victoryPrefix}: $fighter2Name';
                winnerColor = VerdictStyle.fighterRed;
              }

              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.debateTopicLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      topic,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 40),

                    // Карточка Победителя (glass)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 30, horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0x661D2233),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: winnerColor.withValues(alpha: 0.5),
                                width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: winnerColor.withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.emoji_events,
                                  size: 60, color: winnerColor),
                              const SizedBox(height: 16),
                              Text(
                                winnerName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: winnerColor,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Статистика голосов
                    GlassCard(
                      borderRadius: BorderRadius.circular(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: _buildStatCol(fighter1Name,
                                votes1.toString(),
                                VerdictStyle.fighterBlue, context),
                          ),
                          Text(l10n.versusLabel,
                              style: const TextStyle(
                                  color: Color(0xFFFFA500),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          Expanded(
                            child: _buildStatCol(fighter2Name,
                                votes2.toString(),
                                VerdictStyle.fighterRed, context),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),

                    // Кнопка возврата
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const HomeScreen(),
                              transitionsBuilder: (context, animation,
                                      secondaryAnimation, child) =>
                                  FadeTransition(
                                      opacity: animation, child: child),
                              transitionDuration:
                                  const Duration(milliseconds: 200),
                            ),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VerdictStyle.accentGold,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text(l10n.backToHome,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCol(
      String name, String votes, Color color, BuildContext context) {
    return Column(
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '$votes ${AppLocalizations.of(context)!.votesLabel}',
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
