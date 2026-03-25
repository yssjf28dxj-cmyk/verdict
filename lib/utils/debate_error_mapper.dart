import 'package:cloud_functions/cloud_functions.dart';

import '../l10n/app_localizations.dart';

String mapCallableError(
  AppLocalizations l10n,
  FirebaseFunctionsException error, {
  String? fallbackMessage,
}) {
  final details = error.details;
  final reason = details is Map ? details['reason']?.toString() ?? '' : '';

  switch (reason) {
    case 'CREATE_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'CREATE_TOPIC_INVALID':
      return l10n.enterTopicValidation;
    case 'CREATE_INVITED_REQUIRED':
      return l10n.directInviteNeedsOpponent;
    case 'CREATE_PRIVATE_INVITED_REQUIRED':
      return l10n.privateNeedsOpponent;
    case 'CREATE_SELF_INVITE':
      return l10n.cannotAcceptOwnChallenge;
    case 'CREATE_MODE_INVALID':
    case 'CREATE_VISIBILITY_INVALID':
    case 'CREATE_LANGUAGE_INVALID':
    case 'CREATE_REGION_INVALID':
    case 'CREATE_DURATION_INVALID':
    case 'CREATE_ROUNDS_INVALID':
      return fallbackMessage ?? l10n.errorPrefix;
    case 'ACCESS_REQUEST_AUTH_REQUIRED':
      return l10n.loginToRequestAccess;
    case 'ACCESS_REQUEST_NOT_FOUND':
      return l10n.debateNotFound;
    case 'ACCESS_REQUEST_ALREADY_SENT':
      return l10n.requestAlreadySent;
    case 'ACCESS_REQUEST_DEBATE_ID_REQUIRED':
      return fallbackMessage ?? l10n.errorPrefix;
    case 'CANCEL_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'CANCEL_NOT_FOUND':
      return l10n.debateNotFound;
    case 'CANCEL_NOT_CREATOR':
      return l10n.accessRestricted;
    case 'CANCEL_STATUS_INVALID':
      return l10n.debateAlreadyActive;
    case 'VOTE_DEBATE_ID_REQUIRED':
      return fallbackMessage ?? l10n.errorPrefix;
    case 'VOTE_STATUS_DEBATE_ID_REQUIRED':
      return fallbackMessage ?? l10n.errorPrefix;
    case 'ADVANCE_DEBATE_ID_REQUIRED':
      return fallbackMessage ?? l10n.errorPrefix;
    case 'MODERATE_DEBATE_ID_REQUIRED':
    case 'MODERATE_TARGET_UID_REQUIRED':
    case 'MODERATE_ACTION_INVALID':
      return fallbackMessage ?? l10n.errorPrefix;
    case 'MODERATE_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'MODERATE_NOT_FOUND':
      return l10n.debateNotFound;
    case 'MODERATE_NOT_CREATOR':
      return l10n.accessRestricted;
    case 'MIGRATION_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'MIGRATION_ADMIN_REQUIRED':
      return l10n.accessRestricted;
    case 'MIGRATION_ALREADY_RUNNING':
      return fallbackMessage ?? l10n.errorPrefix;
  }

  final msg = (error.message ?? '').trim();
  if (msg.isNotEmpty) return msg;
  return fallbackMessage ?? '${l10n.errorPrefix}: ${error.code}';
}

String mapDebateCallableError(
  AppLocalizations l10n,
  FirebaseFunctionsException error, {
  String? fallbackMessage,
}) {
  final details = error.details;
  final reason = details is Map ? details['reason']?.toString() ?? '' : '';

  switch (reason) {
    case 'TURN_NOT_ACTIVE_SPEAKER':
      return l10n.notYourTurn;
    case 'TURN_NOT_ASSIGNED':
      return l10n.penaltyApplyFailed;
    case 'TURN_NOT_FIGHTER':
      return l10n.accessRestricted;
    case 'ROUND_NOT_ACTIVE':
      return l10n.penaltyApplyFailed;
    case 'PENALTY_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'PENALTY_NOT_FOUND':
      return l10n.debateNotFound;
    case 'PENALTY_DEBATE_FINISHED':
      return l10n.penaltyApplyFailed;
    case 'PENALTY_DEBATE_NOT_PLAYABLE':
      return l10n.penaltyApplyFailed;
    case 'PENALTY_DEBATE_ID_REQUIRED':
    case 'PENALTY_SECONDS_INVALID':
      return l10n.penaltyApplyFailed;
    case 'MESSAGE_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'MESSAGE_NOT_FOUND':
      return l10n.debateNotFound;
    case 'MESSAGE_DEBATE_FINISHED':
      return l10n.debateAlreadyActive;
    case 'MESSAGE_ACCESS_DENIED':
      return l10n.accessRestricted;
    case 'MESSAGE_DEBATE_NOT_LIVE':
      return l10n.waitingOpponent;
    case 'MESSAGE_BAD_STATUS':
      return l10n.debateAlreadyActive;
    case 'TURN_TIME_EXPIRED':
      return l10n.waitForOpponentTurn;
    case 'MESSAGE_DEBATE_ID_REQUIRED':
    case 'MESSAGE_TEXT_EMPTY':
      return l10n.errorPrefix;
    case 'PENALTY_NO_OPPONENT':
      return l10n.penaltyApplyFailed;
    case 'PENALTY_RATE_LIMIT':
      return (error.message ?? '').trim().isNotEmpty
          ? (error.message ?? '').trim()
          : l10n.penaltyApplyFailed;
    case 'ACCEPT_NOT_INVITED_USER':
      return l10n.noAccessToInviteAccept;
    case 'ACCEPT_NOT_FOUND':
      return l10n.debateNotFound;
    case 'ACCEPT_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'ACCEPT_DEBATE_ID_REQUIRED':
      return l10n.acceptChallengeFailed;
    case 'ACCEPT_PROPOSAL_DURATION_INVALID':
      return l10n.acceptChallengeFailed;
    case 'ACCEPT_PROPOSAL_ROUNDS_INVALID':
      return l10n.acceptChallengeFailed;
    case 'ACCEPT_OPPONENT_ALREADY_SET':
      return l10n.debateAlreadyActive;
    case 'ACCEPT_SELF_CHALLENGE':
      return l10n.cannotAcceptOwnChallenge;
    case 'ACCEPT_ALREADY_FINISHED':
      return l10n.debateAlreadyActive;
    case 'ACCEPT_STATUS_INVALID':
      return l10n.acceptChallengeFailed;
    case 'ADVANCE_NOT_PARTICIPANT':
      return l10n.accessRestricted;
    case 'ADVANCE_NOT_FOUND':
      return l10n.debateNotFound;
    case 'ADVANCE_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'ROUND_NOT_ENDED':
      return l10n.waitingYourTurn;
    case 'VOTE_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'VOTE_SIDE_INVALID':
    case 'VOTE_SCOPE_INVALID':
      return l10n.errorPrefix;
    case 'VOTE_NOT_FOUND':
      return l10n.debateNotFound;
    case 'VOTE_ACCESS_DENIED':
      return l10n.accessRestricted;
    case 'VOTE_DEBATE_FINISHED':
      return l10n.debateAlreadyActive;
    case 'VOTE_DEBATE_NOT_LIVE':
      return l10n.waitingOpponent;
    case 'VOTE_FIGHTER_FORBIDDEN':
      return l10n.accessRestricted;
    case 'VOTE_ALREADY_CAST':
      return l10n.alreadyVoted;
    case 'VOTE_STATUS_AUTH_REQUIRED':
      return l10n.authRequired;
    case 'VOTE_STATUS_SCOPE_INVALID':
      return l10n.errorPrefix;
    case 'VOTE_STATUS_NOT_FOUND':
      return l10n.debateNotFound;
    case 'VOTE_STATUS_ACCESS_DENIED':
      return l10n.accessRestricted;
    default:
      return mapCallableError(
        l10n,
        error,
        fallbackMessage: fallbackMessage,
      );
  }
}
