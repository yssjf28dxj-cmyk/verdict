import '../services/pending_challenge.dart';
import 'package:verdict/firebase_session.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../widgets/debate_setup_controls.dart';
import '../utils/debate_error_mapper.dart';
import '../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class CreateDebateScreen extends StatefulWidget {
  const CreateDebateScreen({super.key});

  @override
  State<CreateDebateScreen> createState() => _CreateDebateScreenState();
}

class _CreateDebateScreenState extends State<CreateDebateScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _invitedUserIdController =
      TextEditingController();
  bool _isLoading = false;
  int _selectedDuration = 180;
  int _selectedRounds = 3;
  String _creationMode = 'public_feed';
  String _visibilityMode = 'public';
  String _languageCode = 'ru';
  String _region = 'global';

  // ─── Sanitizers ───────────────────────────────────────────────
  String _sanitizeLanguageCode(String v) =>
      const <String>{'ru', 'en', 'ar'}.contains(v) ? v : 'ru';
  String _sanitizeRegion(String v) =>
      const <String>{'global', 'cis', 'mena', 'europe_africa'}.contains(v)
          ? v
          : 'global';
  String _sanitizeCreationMode(String v) =>
      const <String>{'public_feed', 'direct_invite'}.contains(v)
          ? v
          : 'public_feed';
  String _sanitizeVisibilityMode(String v) =>
      const <String>{'public', 'request_only', 'private'}.contains(v)
          ? v
          : 'public';

  Map<String, dynamic> _buildPayload(String invitedUserId) {
    final creationMode = _sanitizeCreationMode(_creationMode);
    var visibilityMode = _sanitizeVisibilityMode(_visibilityMode);
    if (creationMode == 'direct_invite') visibilityMode = 'private';
    return {
      'topic': _topicController.text.trim(),
      'durationSeconds': _selectedDuration,
      'totalRounds': _selectedRounds,
      'creationMode': creationMode,
      'visibilityMode': visibilityMode,
      'languageCode': _sanitizeLanguageCode(_languageCode),
      'region': _sanitizeRegion(_region),
      'invitedUserId':
          creationMode == 'direct_invite' || visibilityMode == 'private'
              ? invitedUserId
              : '',
    };
  }

  String _resolveCreateError(
      AppLocalizations l10n, FirebaseFunctionsException e) {
    final mapped =
        mapCallableError(l10n, e, fallbackMessage: 'Server error (${e.code})');
    if (mapped.trim().isNotEmpty &&
        mapped.trim().toUpperCase() != 'NOT_FOUND') {
      return mapped;
    }
    return (e.message?.trim().isNotEmpty == true)
        ? e.message!
        : 'Request failed (${e.code})';
  }

  Future<void> _createDebate(AppLocalizations l10n) async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final invitedUserId = _invitedUserIdController.text.trim();
    final payload = _buildPayload(invitedUserId);
    try {
      final uid = appAuth.currentUser?.uid;
      if (uid == null) throw StateError(l10n.authRequired);
      final callable = appFunctions.httpsCallable('createDebate',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      if (payload['creationMode'] == 'direct_invite' && invitedUserId.isEmpty) {
        throw StateError(l10n.directInviteNeedsOpponent);
      }
      final debateId = await PendingChallenge(uid).send(payload,
          submit: (request) async => (await callable.call(request)).data,
          isCurrentSession: () => mounted && appAuth.currentUser?.uid == uid);
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.replace('/lobby/$debateId');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // Preserve the persisted request ID for a safe manual retry of these terms.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_resolveCreateError(l10n, e))),
      );
      setState(() => _isLoading = false);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${l10n.errorPrefix}: $e')));
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    _invitedUserIdController.dispose();
    super.dispose();
  }

  // ─── UI helpers ───────────────────────────────────────────────

  /// A compact pill chip.
  Widget _chip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: ChoiceChip(
        selected: selected,
        onSelected: _isLoading ? null : (_) => onTap(),
        avatar: icon == null ? null : Icon(icon, size: 18),
        showCheckmark: true,
        label: Text(label),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  /// Compact section card with title + icon.
  Widget _section({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF191B20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFF3F4F6),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              )),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showInviteField =
        _creationMode == 'direct_invite' || _visibilityMode == 'private';

    final scheme = Theme.of(context).colorScheme.copyWith(
          primary: const Color(0xFFE6B85C),
          onPrimary: const Color(0xFF101114),
          secondaryContainer: const Color(0xFF3A3020),
          onSecondaryContainer: const Color(0xFFF3D69B),
          surface: const Color(0xFF191B20),
          onSurface: const Color(0xFFF3F4F6),
          outline: const Color(0xFF50545D),
        );
    return Theme(
        data: Theme.of(context).copyWith(colorScheme: scheme),
        child: Scaffold(
          backgroundColor: const Color(0xFF101114),
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: Colors.white,
            title: Text(
              l10n.createBattleTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
                fontSize: 18,
              ),
            ),
          ),
          body: Stack(
            children: [
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ── Topic ──────────────────────────────────────
                                _section(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  title: l10n.debateTopicLabel,
                                  child: TextFormField(
                                    controller: _topicController,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 1.4),
                                    decoration: InputDecoration(
                                      hintText: l10n.enterTopic,
                                      hintStyle: const TextStyle(
                                          color: Colors.white30, fontSize: 15),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE6B85C),
                                            width: 1.5),
                                      ),
                                      filled: true,
                                      fillColor:
                                          Colors.white.withValues(alpha: 0.06),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? l10n.enterTopicValidation
                                            : null,
                                    textInputAction: TextInputAction.done,
                                    maxLines: 2,
                                    minLines: 1,
                                  ),
                                ),

                                _section(
                                    icon: Icons.tune_rounded,
                                    title: l10n.modesLabel,
                                    child: DebateSetupControls(
                                        duration: _selectedDuration,
                                        rounds: _selectedRounds,
                                        visibility: _visibilityMode,
                                        directInvite:
                                            _creationMode == 'direct_invite',
                                        enabled: !_isLoading,
                                        onDuration: (value) => setState(
                                            () => _selectedDuration = value),
                                        onRounds: (value) => setState(
                                            () => _selectedRounds = value),
                                        onDirectInvite: (value) => setState(() {
                                              _creationMode = value
                                                  ? 'direct_invite'
                                                  : 'public_feed';
                                              _visibilityMode =
                                                  value ? 'private' : 'public';
                                            }),
                                        onVisibility: (value) => setState(() {
                                              _visibilityMode = value;
                                              _creationMode = value == 'private'
                                                  ? 'direct_invite'
                                                  : 'public_feed';
                                            }))),
                                AnimatedSize(
                                    duration: const Duration(milliseconds: 180),
                                    child: showInviteField
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 16),
                                            child: TextFormField(
                                                controller:
                                                    _invitedUserIdController,
                                                style: const TextStyle(
                                                    color: Colors.white),
                                                decoration: InputDecoration(
                                                    labelText: l10n.opponentId,
                                                    prefixIcon: const Icon(
                                                        Icons.person_outline),
                                                    border:
                                                        const OutlineInputBorder()),
                                                validator: (value) =>
                                                    value == null ||
                                                            value.trim().isEmpty
                                                        ? l10n.enterOpponentId
                                                        : null))
                                        : const SizedBox.shrink()),

                                // ── Language & Region ──────────────────────────
                                _section(
                                  icon: Icons.language_rounded,
                                  title: l10n.languageRegionLabel,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          _chip(
                                              selected: _languageCode == 'ru',
                                              label: 'RU',
                                              onTap: () => setState(
                                                  () => _languageCode = 'ru')),
                                          _chip(
                                              selected: _languageCode == 'en',
                                              label: 'EN',
                                              onTap: () => setState(
                                                  () => _languageCode = 'en')),
                                          _chip(
                                              selected: _languageCode == 'ar',
                                              label: 'AR',
                                              onTap: () => setState(
                                                  () => _languageCode = 'ar')),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          _chip(
                                              selected: _region == 'global',
                                              label: l10n.regionGlobal,
                                              onTap: () => setState(
                                                  () => _region = 'global')),
                                          _chip(
                                              selected: _region == 'cis',
                                              label: l10n.regionCis,
                                              onTap: () => setState(
                                                  () => _region = 'cis')),
                                          _chip(
                                              selected: _region == 'mena',
                                              label: l10n.regionMena,
                                              onTap: () => setState(
                                                  () => _region = 'mena')),
                                          _chip(
                                              selected:
                                                  _region == 'europe_africa',
                                              label: l10n.regionEuAf,
                                              onTap: () => setState(() =>
                                                  _region = 'europe_africa')),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // ── Publish button ─────────────────────────────
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: 54),
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => _createDebate(l10n),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE6B85C),
                                      foregroundColor: Colors.black,
                                      disabledBackgroundColor:
                                          const Color(0xFFE6B85C)
                                              .withValues(alpha: 0.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 16),
                                      elevation: 0,
                                      shadowColor: const Color(0xFFE6B85C),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                color: Colors.black,
                                                strokeWidth: 2.5),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.bolt_rounded,
                                                  size: 20),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                  child: Text(
                                                l10n.publishChallenge,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ))),
                ),
              ),
            ],
          ),
        ));
  }
}
