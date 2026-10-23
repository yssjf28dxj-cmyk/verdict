import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/style_utils.dart';

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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + kToolbarHeight + 12,
        16,
        8,
      ),
      child: GlassCard(
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
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0x662A3147),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('language-$feedLanguage'),
                    initialValue: feedLanguage,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            _safeLocalizedText(
                                l10n.languageAll, 'Language: all'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'ru',
                          child: Text(
                            l10n.themeLanguageRU,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'en',
                          child: Text(
                            l10n.themeLanguageEN,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'ar',
                          child: Text(
                            l10n.themeLanguageAR,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                    ],
                    onChanged: (v) {
                      if (v != null) onLanguageChanged(v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('region-$feedRegion'),
                    initialValue: feedRegion,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'global',
                          child: Text(
                            _safeLocalizedText(l10n.regionGlobal, 'Global'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'cis',
                          child: Text(
                            l10n.regionCis,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'mena',
                          child: Text(
                            l10n.regionMena,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                      DropdownMenuItem(
                          value: 'europe_africa',
                          child: Text(
                            l10n.regionEuAf,
                            maxLines: 1,
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
    );
  }
}
