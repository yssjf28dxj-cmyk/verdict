import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'Welcome to VERDICT',
      'description':
          'The ultimate intellectual combat platform. Prepare to defend your ideas and challenge others in real-time.',
      'icon': Icons.gavel_rounded,
    },
    {
      'title': 'Choose a Battle',
      'description':
          'Select a specific topic to debate or jump right into a random room. The arena awaits.',
      'icon': Icons.sports_mma_rounded,
    },
    {
      'title': 'Debate Rules',
      'description':
          'Strict timers keep the action moving. Alternating turns ensure fairness. No interruptions allowed.',
      'icon': Icons.timer_rounded,
    },
    {
      'title': 'The Verdict',
      'description':
          'When the time is up, an AI or live audience will judge the winner based on arguments, logic, and delivery.',
      'icon': Icons.emoji_events_rounded,
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    if (context.mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color bgColor = Color(0xFF0B0E14);
    const Color goldColor = Color(0xFFFFD700);
    const Color whiteColor = Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _finish,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _pages[index]['icon'] as IconData,
                          size: 100,
                          color: goldColor,
                        ),
                        const SizedBox(height: 48),
                        Text(
                          _pages[index]['title'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: goldColor,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _pages[index]['description'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: whiteColor,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Bar
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  // Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        width: _currentPage == index ? 24.0 : 8.0,
                        height: 8.0,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? goldColor : Colors.white24,
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Next / Finish Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _onNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldColor,
                        foregroundColor: bgColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPage == _pages.length - 1 ? "LET'S FIGHT!" : 'NEXT',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
