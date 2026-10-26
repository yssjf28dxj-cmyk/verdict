import '../widgets/test_profile_switcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/arena_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/home_debate_list.dart';
import '../widgets/global_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.debateList});

  /// Optional view injection for layout previews; normal navigation uses the live feed.
  final Widget? debateList;

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
    return Theme(
        data: ArenaTheme.from(Theme.of(context)),
        child: Scaffold(
          backgroundColor: ArenaTheme.background,
          appBar: AppBar(
            title: Text(_safeLocalizedText(l10n.appTitle, 'VERDICT')),
            centerTitle: false,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              const TestProfileSwitcher(compact: true),
              IconButton(
                tooltip: l10n.profileTab,
                icon: const Icon(Icons.person_outline),
                onPressed: () => context.push('/profile'),
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
                builder: (context, constraints) => Column(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight * 0.5),
                          child: SingleChildScrollView(
                              child: HomeSearchBar(
                            searchController: _searchController,
                            feedLanguage: _feedLanguage,
                            feedRegion: _feedRegion,
                            onSearchChanged: (v) =>
                                setState(() => _search = v.trim()),
                            onLanguageChanged: (v) =>
                                setState(() => _feedLanguage = v),
                            onRegionChanged: (v) =>
                                setState(() => _feedRegion = v),
                          )),
                        ),
                        Expanded(
                            child: widget.debateList ??
                                HomeDebateList(
                                  searchQuery: _search,
                                  feedLanguage: _feedLanguage,
                                  feedRegion: _feedRegion,
                                )),
                      ],
                    )),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => context.push('/create-debate'),
            tooltip: l10n.createDebates,
            backgroundColor: ArenaTheme.accent,
            foregroundColor: ArenaTheme.background,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.add),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: const GlobalBottomNav(currentIndex: 0),
        ));
  }
}
