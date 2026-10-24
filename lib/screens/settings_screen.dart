import 'package:verdict/firebase_session.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_localizations.dart';

import '../painters/chat_pattern_painter.dart';
import '../services/admin_service.dart';
import '../widgets/push_settings_card.dart';
import '../services/app_locale_controller.dart';
import '../services/sound_service.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/style_utils.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _canUseMigrationTools = false;
  bool _checkingMigrationAccess = true;
  bool _migrationLoading = false;
  String _migrationResult = '';

  final AdminService _adminService = AdminService();
  final FirebaseFunctions _functions = appFunctions;

  @override
  void initState() {
    super.initState();
    _loadMigrationAccess();
  }

  Future<void> _loadMigrationAccess() async {
    final hasAccess = await _adminService.hasMigrationAccess();
    if (!mounted) return;
    setState(() {
      _canUseMigrationTools = hasAccess;
      _checkingMigrationAccess = false;
    });
  }

  Future<void> _runMigration({required bool dryRun}) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _migrationLoading = true;
      _migrationResult = '';
    });

    try {
      final callable =
          _functions.httpsCallable('migrateLegacyNamePlaceholders');
      final result = await callable.call({
        'dryRun': dryRun,
        'maxDocsPerCollection': 500,
      });

      final data =
          result.data is Map ? result.data as Map : const <String, dynamic>{};
      final users = data['users'] is Map
          ? data['users'] as Map
          : const <String, dynamic>{};
      final debates = data['debates'] is Map
          ? data['debates'] as Map
          : const <String, dynamic>{};
      final world = data['worldMessages'] is Map
          ? data['worldMessages'] as Map
          : const <String, dynamic>{};
      final messages = data['debateMessages'] is Map
          ? data['debateMessages'] as Map
          : const <String, dynamic>{};

      final summary = StringBuffer()
        ..writeln(dryRun ? l10n.migrationDryRunDone : l10n.migrationApplyDone)
        ..writeln(
            '${l10n.migrationUsers}: ${users['updated'] ?? 0}/${users['scanned'] ?? 0}')
        ..writeln(
            '${l10n.migrationDebates}: ${debates['updated'] ?? 0}/${debates['scanned'] ?? 0}')
        ..writeln(
            '${l10n.migrationWorldMessages}: ${world['updated'] ?? 0}/${world['scanned'] ?? 0}')
        ..write(
            '${l10n.migrationDebateMessages}: ${messages['updated'] ?? 0}/${messages['scanned'] ?? 0}');

      if (!mounted) return;
      setState(() {
        _migrationResult = summary.toString();
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _migrationResult = '${l10n.migrationFailed}: ${mapCallableError(
          l10n,
          e,
          fallbackMessage: e.code,
        )}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _migrationResult = '${l10n.migrationFailed}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _migrationLoading = false;
        });
      }
    }
  }

  Future<void> _confirmAndRunApplyMigration() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.migrationConfirmTitle),
          content: Text(l10n.migrationConfirmBody),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: Text(l10n.close),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: Text(l10n.applyMigration),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _runMigration(dryRun: false);
    }
  }

  String _localeName(AppLocalizations l10n, Locale locale) {
    switch (locale.languageCode) {
      case 'ru':
        return l10n.themeLanguageRU;
      case 'en':
        return l10n.themeLanguageEN;
      case 'ar':
        return l10n.themeLanguageAR;
      case 'zh':
        return l10n.themeLanguageZH;
      case 'es':
        return l10n.themeLanguageES;
      case 'fr':
        return l10n.themeLanguageFR;
      case 'hi':
        return l10n.themeLanguageHI;
      default:
        return locale.languageCode.toUpperCase();
    }
  }

  Widget _buildFounderMigrationTools(AppLocalizations l10n) {
    // The server checks the migration lock when a dry run or apply is requested.
    // Do not infer an unlocked state from a denied private Firestore read.
    final actionsDisabled = _migrationLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.migrationToolsTitle.toUpperCase(),
          style: VerdictStyle.headingStyle,
        ),
        const SizedBox(height: 10),
        Text(
          l10n.migrationToolsSubtitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    actionsDisabled ? null : () => _runMigration(dryRun: true),
                child: Text(l10n.runDryMigration),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    actionsDisabled ? null : _confirmAndRunApplyMigration,
                child: Text(l10n.applyMigration),
              ),
            ),
          ],
        ),
        if (_migrationLoading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_migrationResult.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              _migrationResult,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSoundCard(AppLocalizations l10n) {
    return GlassCard(
      child: Row(
        children: [
          const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.settingsTitle.contains('Settings')
                  ? 'Sound Effects'
                  : 'Звуковые эффекты',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          StatefulBuilder(
            builder: (context, setSwitchState) {
              return Switch.adaptive(
                value: SoundService.instance.soundEnabled,
                activeTrackColor: VerdictStyle.accentGold,
                onChanged: (value) async {
                  await SoundService.instance.setEnabled(value);
                  setSwitchState(() {});
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialCard(AppLocalizations l10n) {
    return GestureDetector(
      onTap: () {
        context.push('/rules');
      },
      child: GlassCard(
        child: Row(
          children: [
            const Icon(Icons.help_outline_rounded,
                color: Colors.white70, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.settingsTitle.contains('Settings')
                    ? 'How it works'
                    : 'Как это работает',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageCard(AppLocalizations l10n) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settings_section_general,
            style: VerdictStyle.headingStyle,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.language,
                color: Color(0xFFFFD180),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.settings_language_title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: AppLocaleController.supportedLocales.map((loc) {
                    final selected = AppLocaleController.instance.locale == loc;
                    return ChoiceChip(
                      selected: selected,
                      onSelected: (_) {
                        AppLocaleController.instance.setLocale(loc);
                      },
                      label: Text(_localeName(l10n, loc)),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0AFFFFFF)),
            ),
          ),
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + kToolbarHeight + 12,
              16,
              24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTutorialCard(l10n),
                    const SizedBox(height: 14),
                    if (testProfilesEnabled) const PushSettingsCard(),
                    _buildLanguageCard(l10n),
                    const SizedBox(height: 14),
                    _buildSoundCard(l10n),
                    if (_checkingMigrationAccess) ...[
                      const SizedBox(height: 14),
                      const GlassCard(
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    ],
                    if (!_checkingMigrationAccess && _canUseMigrationTools) ...[
                      const SizedBox(height: 14),
                      GlassCard(
                        child: _buildFounderMigrationTools(l10n),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
