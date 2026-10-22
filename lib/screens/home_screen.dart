import '../widgets/test_profile_switcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/home_debate_list.dart';
import '../widgets/global_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _search = '';
  String _feedLanguage = 'all';
  String _feedRegion = 'global';
  final TextEditingController _searchController = TextEditingController();

  String _safeLocalizedText(String raw, String fallback) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.toUpperCase() == 'NOT_FOUND') {
      return fallback;
    }
    return normalized;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        title: Text(_safeLocalizedText(l10n.appTitle, 'VERDICT')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          const TestProfileSwitcher(),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.push('/profile'),
          ),
        ],
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
              HomeSearchBar(
                searchController: _searchController,
                feedLanguage: _feedLanguage,
                feedRegion: _feedRegion,
                onSearchChanged: (v) => setState(() => _search = v.trim()),
                onLanguageChanged: (v) => setState(() => _feedLanguage = v),
                onRegionChanged: (v) => setState(() => _feedRegion = v),
              ),
              Expanded(
                child: HomeDebateList(
                  searchQuery: _search,
                  feedLanguage: _feedLanguage,
                  feedRegion: _feedRegion,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-debate'),
        icon: const Icon(Icons.add),
        label: Text(l10n.createDebates),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: const GlobalBottomNav(currentIndex: 0),
    );
  }
}
