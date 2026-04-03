import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../painters/chat_pattern_painter.dart';
import '../utils/debate_error_mapper.dart';
import '../utils/style_utils.dart';
import '../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class CreateDebateScreen extends StatefulWidget {
  const CreateDebateScreen({super.key});

  @override
  State<CreateDebateScreen> createState() => _CreateDebateScreenState();
}

class _CreateDebateScreenState extends State<CreateDebateScreen> {
  static const List<int> _durationOptions = <int>[
    30,
    60,
    90,
    120,
    180,
    300,
    420,
    600,
  ];

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _invitedUserIdController =
      TextEditingController();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  bool _isLoading = false;
  int _selectedDuration = 180;
  int _selectedRounds = 3;
  String _creationMode = 'public_feed';
  String _visibilityMode = 'public';
  String _languageCode = 'ru';
  String _region = 'global';

  String _sanitizeLanguageCode(String value) {
    const allowed = <String>{'ru', 'en', 'ar'};
    return allowed.contains(value) ? value : 'ru';
  }

  String _sanitizeRegion(String value) {
    const allowed = <String>{'global', 'cis', 'mena', 'europe_africa'};
    return allowed.contains(value) ? value : 'global';
  }

  String _sanitizeCreationMode(String value) {
    const allowed = <String>{'public_feed', 'direct_invite'};
    return allowed.contains(value) ? value : 'public_feed';
  }

  String _sanitizeVisibilityMode(String value) {
    const allowed = <String>{'public', 'request_only', 'private'};
    return allowed.contains(value) ? value : 'public';
  }

  Map<String, dynamic> _buildCreateDebatePayload(String invitedUserId) {
    final creationMode = _sanitizeCreationMode(_creationMode);
    var visibilityMode = _sanitizeVisibilityMode(_visibilityMode);

    // Direct invite must stay private on the backend contract.
    if (creationMode == 'direct_invite') {
      visibilityMode = 'private';
    }

    return {
      'topic': _topicController.text.trim(),
      'durationSeconds': _selectedDuration,
      'totalRounds': _selectedRounds,
      'creationMode': creationMode,
      'visibilityMode': visibilityMode,
      'languageCode': _sanitizeLanguageCode(_languageCode),
      'region': _sanitizeRegion(_region),
      'invitedUserId': invitedUserId,
    };
  }

  String _safeText(String raw, String fallback) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.toUpperCase() == 'NOT_FOUND') {
      return fallback;
    }
    return normalized;
  }

  String? _extractDebateId(dynamic payload) {
    if (payload is String) {
      final value = payload.trim();
      if (value.isNotEmpty) return value;
    }

    if (payload is Map) {
      final direct = (payload['debateId'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;

      final nestedData = payload['data'];
      if (nestedData is Map) {
        final nestedId = (nestedData['debateId'] ?? '').toString().trim();
        if (nestedId.isNotEmpty) return nestedId;
      }

      final result = payload['result'];
      if (result is Map) {
        final resultId = (result['debateId'] ?? '').toString().trim();
        if (resultId.isNotEmpty) return resultId;
      }
    }
    return null;
  }

  String _extractBackendErrorFromPayload(dynamic payload) {
    if (payload is Map) {
      final direct =
          (payload['message'] ?? payload['error'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;

      final reason = payload['reason']?.toString().trim() ?? '';
      if (reason.isNotEmpty) return reason;

      final nested = payload['data'];
      if (nested is Map) {
        final nestedMessage =
            (nested['message'] ?? nested['error'] ?? '').toString().trim();
        if (nestedMessage.isNotEmpty) return nestedMessage;
        final nestedReason = nested['reason']?.toString().trim() ?? '';
        if (nestedReason.isNotEmpty) return nestedReason;
      }
    }
    return '';
  }

  String _resolveCreateErrorMessage(
    AppLocalizations l10n,
    FirebaseFunctionsException error,
  ) {
    final mapped = mapCallableError(
      l10n,
      error,
      fallbackMessage: 'Server error (${error.code})',
    );
    if (mapped.trim().isNotEmpty &&
        mapped.trim().toUpperCase() != 'NOT_FOUND') {
      return mapped;
    }

    final details = error.details;
    final reason =
        details is Map ? (details['reason'] ?? '').toString().trim() : '';
    final backendMessage = (error.message ?? '').trim();
    if (backendMessage.isNotEmpty) return backendMessage;
    if (reason.isNotEmpty) return reason;
    return 'Request failed (${error.code})';
  }

  void _goToLobby(String debateId) {
    context.replace('/lobby/$debateId');
  }

  Future<void> _createDebate(AppLocalizations l10n) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final invitedUserId = _invitedUserIdController.text.trim();
    final payload = _buildCreateDebatePayload(invitedUserId);
    final callable = _functions.httpsCallable(
      'createDebate',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError(
            _safeText(l10n.authRequired, 'Authentication required.'));
      }
      if (payload['creationMode'] == 'direct_invite' && invitedUserId.isEmpty) {
        throw StateError(_safeText(l10n.directInviteNeedsOpponent,
            'Direct invite requires opponent ID.'));
      }
      if (payload['visibilityMode'] == 'private' && invitedUserId.isEmpty) {
        throw StateError(_safeText(
            l10n.privateNeedsOpponent, 'Private debate requires opponent ID.'));
      }

      final res = await callable.call(payload);
      final debateId = _extractDebateId(res.data);
      if (debateId == null) {
        final payloadError = _extractBackendErrorFromPayload(res.data);
        final noIdMessage = _safeText(
          l10n.serverNoDebateId,
          'Backend did not return debateId.',
        );
        throw StateError(
          payloadError.isNotEmpty
              ? payloadError
              : '$noIdMessage Response: ${res.data}',
        );
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      _goToLobby(debateId);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'createDebate FirebaseFunctionsException: code=${e.code}, message=${e.message}, details=${e.details}');
      if (!mounted) return;
      final retryableCodes = {
        'internal',
        'not-found',
        'unavailable',
        'unimplemented',
      };

      if (!retryableCodes.contains(e.code)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_resolveCreateErrorMessage(l10n, e)),
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      try {
        await Future.delayed(const Duration(milliseconds: 900));
        final retry = await callable.call(payload);
        final debateId = _extractDebateId(retry.data);
        if (debateId == null) {
          final payloadError = _extractBackendErrorFromPayload(retry.data);
          final noIdMessage = _safeText(
            l10n.serverNoDebateId,
            'Backend did not return debateId.',
          );
          throw StateError(
            payloadError.isNotEmpty
                ? payloadError
                : '$noIdMessage Response: ${retry.data}',
          );
        }
        if (!mounted) return;
        setState(() => _isLoading = false);
        _goToLobby(debateId);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_resolveCreateErrorMessage(l10n, e)),
          ),
        );
        setState(() => _isLoading = false);
      }
    } on StateError catch (e) {
      if (!mounted) return;
      final text = e.message.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(text.isNotEmpty ? text : 'Create debate failed.')),
      );
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      final prefix = _safeText(l10n.errorPrefix, 'Error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$prefix: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    _invitedUserIdController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0x662A3147),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Color(0xFFFFA500), width: 2),
      ),
    );
  }

  String _durationChipLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainderSeconds = seconds % 60;
    final ss = remainderSeconds.toString().padLeft(2, '0');
    return '$minutes:$ss';
  }

  Widget _buildChoiceChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFA500) : const Color(0xFF1D2233),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? const Color(0xFFFFA500) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: VerdictStyle.bg,
      appBar: AppBar(
        backgroundColor: VerdictStyle.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          l10n.createBattleTitle,
          style: const TextStyle(
            color: Color(0xFFFFA500),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ChatPatternPainter(color: Color(0x0B000000)),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: GlassCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.debateTopicLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _topicController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: _inputDecoration(l10n.enterTopic),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? l10n.enterTopicValidation
                            : null,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.roundTimeLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _durationOptions
                            .map(
                              (seconds) => _buildChoiceChip(
                                selected: _selectedDuration == seconds,
                                label: _durationChipLabel(seconds),
                                onTap: () =>
                                    setState(() => _selectedDuration = seconds),
                              ),
                            )
                            .toList(),
                      ),
                      Text(
                        l10n.roundsLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            selected: _selectedRounds == 1,
                            label: l10n.oneRound,
                            onTap: () => setState(() => _selectedRounds = 1),
                          ),
                          _buildChoiceChip(
                            selected: _selectedRounds == 3,
                            label: l10n.threeRounds,
                            onTap: () => setState(() => _selectedRounds = 3),
                          ),
                          _buildChoiceChip(
                            selected: _selectedRounds == 5,
                            label: l10n.fiveRounds,
                            onTap: () => setState(() => _selectedRounds = 5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.modesLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            selected: _creationMode == 'public_feed',
                            label: l10n.publicFeed,
                            onTap: () => setState(() {
                              _creationMode = 'public_feed';
                              if (_visibilityMode == 'private') {
                                _visibilityMode = 'request_only';
                              }
                            }),
                          ),
                          _buildChoiceChip(
                            selected: _creationMode == 'direct_invite',
                            label: l10n.directInvite,
                            onTap: () =>
                                setState(() => _creationMode = 'direct_invite'),
                          ),
                          _buildChoiceChip(
                            selected: _visibilityMode == 'public',
                            label: l10n.publicMode,
                            onTap: () =>
                                setState(() => _visibilityMode = 'public'),
                          ),
                          _buildChoiceChip(
                            selected: _visibilityMode == 'request_only',
                            label: l10n.requestOnly,
                            onTap: () => setState(
                                () => _visibilityMode = 'request_only'),
                          ),
                          _buildChoiceChip(
                            selected: _visibilityMode == 'private',
                            label: l10n.privateMode,
                            onTap: () => setState(() {
                              _visibilityMode = 'private';
                              _creationMode = 'direct_invite';
                            }),
                          ),
                        ],
                      ),
                      if (_creationMode == 'direct_invite' ||
                          _visibilityMode == 'private') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _invitedUserIdController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                          decoration: _inputDecoration(l10n.opponentId),
                          validator: (v) {
                            if (_creationMode != 'direct_invite') return null;
                            if (v == null || v.trim().isEmpty) {
                              return l10n.enterOpponentId;
                            }
                            return null;
                          },
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        l10n.languageRegionLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            selected: _languageCode == 'ru',
                            label: 'RU',
                            onTap: () => setState(() => _languageCode = 'ru'),
                          ),
                          _buildChoiceChip(
                            selected: _languageCode == 'en',
                            label: 'EN',
                            onTap: () => setState(() => _languageCode = 'en'),
                          ),
                          _buildChoiceChip(
                            selected: _languageCode == 'ar',
                            label: 'AR',
                            onTap: () => setState(() => _languageCode = 'ar'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'global',
                            label: l10n.regionGlobal,
                            onTap: () => setState(() => _region = 'global'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'cis',
                            label: l10n.regionCis,
                            onTap: () => setState(() => _region = 'cis'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'mena',
                            label: l10n.regionMena,
                            onTap: () => setState(() => _region = 'mena'),
                          ),
                          _buildChoiceChip(
                            selected: _region == 'europe_africa',
                            label: l10n.regionEuAf,
                            onTap: () =>
                                setState(() => _region = 'europe_africa'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed:
                              _isLoading ? null : () => _createDebate(l10n),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFA500),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2),
                                )
                              : Text(
                                  l10n.publishChallenge,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
