import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/arena_theme.dart';

class HomeSearchBar extends StatelessWidget {
  final TextEditingController searchController;
  final String feedLanguage;
  final String feedRegion;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onRegionChanged;

  const HomeSearchBar({
    super.key,
    required this.searchController,
    required this.feedLanguage,
    required this.feedRegion,
    required this.onSearchChanged,
    required this.onLanguageChanged,
    required this.onRegionChanged,
  });

  String _safeLocalizedText(String raw, String fallback) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.toUpperCase() == 'NOT_FOUND') {
      return fallback;
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 840),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _safeLocalizedText(
                  l10n.searchDebates,
                  'Search debates',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: ArenaTheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              key: const PageStorageKey('arena-filters'),
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_outlined),
              title: Text(l10n.languageRegionLabel),
              subtitle: Text(
                  '${feedLanguage == 'all' ? l10n.languageAll : feedLanguage.toUpperCase()} · ${switch (feedRegion) {
                'cis' => l10n.regionCis,
                'mena' => l10n.regionMena,
                'europe_africa' => l10n.regionEuAf,
                _ => l10n.regionGlobal,
              }}'),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('language-$feedLanguage'),
                    initialValue: feedLanguage,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: InputDecoration(
                      isDense: false,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            _safeLocalizedText(
                                l10n.languageAll, 'Language: all'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'ru',
                          child: Text(
                            l10n.themeLanguageRU,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'en',
                          child: Text(
                            l10n.themeLanguageEN,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'ar',
                          child: Text(
                            l10n.themeLanguageAR,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                    ],
                    onChanged: (v) {
                      if (v != null) onLanguageChanged(v);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('region-$feedRegion'),
                    initialValue: feedRegion,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: InputDecoration(
                      isDense: false,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'global',
                          child: Text(
                            _safeLocalizedText(l10n.regionGlobal, 'Global'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'cis',
                          child: Text(
                            l10n.regionCis,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'mena',
                          child: Text(
                            l10n.regionMena,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'europe_africa',
                          child: Text(
                            l10n.regionEuAf,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                    ],
                    onChanged: (v) {
                      if (v != null) onRegionChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }
}
