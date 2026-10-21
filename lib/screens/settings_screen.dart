import 'package:verdict/firestore_database.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_localizations.dart';

import '../painters/chat_pattern_painter.dart';
import '../services/admin_service.dart';
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
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = appFirestore;

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

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '...';
    final dt = timestamp.toDate().toLocal();
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  String _migrationStatusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'in_progress':
        return l10n.migrationStatusInProgress;
      case 'failed':
        return l10n.migrationStatusFailed;
      case 'completed':
      default:
        return l10n.migrationStatusCompleted;
    }
  }

  void _showMigrationReportDialog(
    AppLocalizations l10n,
    Map<String, dynamic> data,
  ) {
    final actor = (data['actorEmail'] ?? data['actorUid'] ?? '...').toString();
    final dryRun = data['dryRun'] == true;
    final status = (data['status'] ?? 'completed').toString();
    final users = data['users'] is Map ? data['users'] as Map : const {};
    final debates = data['debates'] is Map ? data['debates'] as Map : const {};
    final worldMessages =
        data['worldMessages'] is Map ? data['worldMessages'] as Map : const {};
    final debateMessages = data['debateMessages'] is Map
        ? data['debateMessages'] as Map
        : const {};
    final errorMessage = (data['errorMessage'] ?? '').toString().trim();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.migrationFullReportTitle),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${l10n.migrationActorLabel}: $actor'),
                Text(
                  '${l10n.migrationModeLabel}: '
                  '${dryRun ? l10n.migrationModeDryRun : l10n.migrationModeApply}',
                ),
                Text(
                  '${l10n.migrationStatusLabel}: '
                  '${_migrationStatusLabel(l10n, status)}',
                ),
                Text(
                  '${l10n.migrationLastRunAtLabel}: '
                  '${_formatTimestamp(data['createdAt'] as Timestamp?)}',
                ),
                if (data['completedAt'] != null)
                  Text(
                    '${l10n.migrationCompletedAtLabel}: '
                    '${_formatTimestamp(data['completedAt'] as Timestamp?)}',
                  ),
                const SizedBox(height: 12),
                Text(
                    '${l10n.migrationUsers}: ${users['updated'] ?? 0}/${users['scanned'] ?? 0}'),
                Text(
                    '${l10n.migrationDebates}: ${debates['updated'] ?? 0}/${debates['scanned'] ?? 0}'),
                Text(
                    '${l10n.migrationWorldMessages}: ${worldMessages['updated'] ?? 0}/${worldMessages['scanned'] ?? 0}'),
                Text(
                    '${l10n.migrationDebateMessages}: ${debateMessages['updated'] ?? 0}/${debateMessages['scanned'] ?? 0}'),
                if (errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.migrationErrorLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(errorMessage),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMigrationLockCard(
    AppLocalizations l10n,
    Map<String, dynamic>? data,
  ) {
    final inProgress = data?['inProgress'] == true;
    if (!inProgress) return const SizedBox.shrink();

    final actor =
        (data?['actorEmail'] ?? data?['actorUid'] ?? '...').toString();
    final startedAt = data?['startedAt'] as Timestamp?;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.migrationInProgressTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.migrationActorLabel}: $actor',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            '${l10n.migrationLastRunAtLabel}: ${_formatTimestamp(startedAt)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFounderMigrationTools(AppLocalizations l10n) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('admin_runtime')
          .doc('migration_lock')
          .snapshots(),
      builder: (context, snapshot) {
        final lockData = snapshot.data?.data();
        final serverLocked = lockData?['inProgress'] == true;
        final actionsDisabled = _migrationLoading || serverLocked;

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
            _buildMigrationLockCard(l10n, lockData),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: actionsDisabled
                        ? null
                        : () => _runMigration(dryRun: true),
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
            _buildLastMigrationRun(l10n),
            _buildMigrationHistory(l10n),
          ],
        );
      },
    );
  }

  Widget _buildLastMigrationRun(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('admin_migration_runs')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        final data = snapshot.data?.docs.isNotEmpty == true
            ? snapshot.data!.docs.first.data()
            : null;
        if (data == null) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.migrationLastRunEmpty,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          );
        }

        final users = data['users'] is Map ? data['users'] as Map : const {};
        final debates =
            data['debates'] is Map ? data['debates'] as Map : const {};
        final worldMessages = data['worldMessages'] is Map
            ? data['worldMessages'] as Map
            : const {};
        final debateMessages = data['debateMessages'] is Map
            ? data['debateMessages'] as Map
            : const {};
        final actor =
            (data['actorEmail'] ?? data['actorUid'] ?? '...').toString();
        final dryRun = data['dryRun'] == true;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.migrationLastRunTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${l10n.migrationModeLabel}: ${dryRun ? l10n.migrationModeDryRun : l10n.migrationModeApply}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${l10n.migrationActorLabel}: $actor',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${l10n.migrationLastRunAtLabel}: ${_formatTimestamp(data['createdAt'] as Timestamp?)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                '${l10n.migrationUsers}: ${users['updated'] ?? 0}/${users['scanned'] ?? 0}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                '${l10n.migrationDebates}: ${debates['updated'] ?? 0}/${debates['scanned'] ?? 0}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                '${l10n.migrationWorldMessages}: ${worldMessages['updated'] ?? 0}/${worldMessages['scanned'] ?? 0}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                '${l10n.migrationDebateMessages}: ${debateMessages['updated'] ?? 0}/${debateMessages['scanned'] ?? 0}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMigrationHistory(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('admin_migration_runs')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.migrationHistoryEmpty,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          );
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.migrationHistoryTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final data = doc.data();
                final actor = (data['actorEmail'] ?? data['actorUid'] ?? '...')
                    .toString();
                final dryRun = data['dryRun'] == true;
                final status = (data['status'] ?? 'completed').toString();
                final users =
                    data['users'] is Map ? data['users'] as Map : const {};
                final debates =
                    data['debates'] is Map ? data['debates'] as Map : const {};
                final worldMessages = data['worldMessages'] is Map
                    ? data['worldMessages'] as Map
                    : const {};
                final debateMessages = data['debateMessages'] is Map
                    ? data['debateMessages'] as Map
                    : const {};
                final errorMessage =
                    (data['errorMessage'] ?? '').toString().trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_formatTimestamp(data['createdAt'] as Timestamp?)}  •  '
                        '${dryRun ? l10n.migrationModeDryRun : l10n.migrationModeApply}  •  '
                        '${_migrationStatusLabel(l10n, status)}  •  $actor',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${l10n.migrationUsers}: ${users['updated'] ?? 0}/${users['scanned'] ?? 0}  ·  '
                        '${l10n.migrationDebates}: ${debates['updated'] ?? 0}/${debates['scanned'] ?? 0}  ·  '
                        '${l10n.migrationWorldMessages}: ${worldMessages['updated'] ?? 0}/${worldMessages['scanned'] ?? 0}  ·  '
                        '${l10n.migrationDebateMessages}: ${debateMessages['updated'] ?? 0}/${debateMessages['scanned'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      if (errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.migrationErrorLabel}: $errorMessage',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFB4B4),
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              _showMigrationReportDialog(l10n, data),
                          child: Text(l10n.viewFullReport),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
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
            const Icon(Icons.help_outline_rounded, color: Colors.white70, size: 22),
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
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
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
