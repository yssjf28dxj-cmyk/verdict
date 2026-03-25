import { HttpsError } from 'firebase-functions/v2/https';

type DebateRecord = Record<string, unknown>;
const LEGACY_OPPONENT_ID_PLACEHOLDERS = new Set([
  'opponent',
  'invited',
  'fighter',
  'оппонент',
  'приглашен',
  'приглашён',
]);

function asString(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function asInt(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

function readRoundIndex(data: DebateRecord): number {
  if (typeof data['roundIndex'] === 'number') return data['roundIndex'] as number;
  if (typeof data['currentRound'] === 'number') return data['currentRound'] as number;
  if (typeof data['round'] === 'number') return data['round'] as number;
  return 1;
}

function hasFinishedImmutableMutation(before: DebateRecord, after: DebateRecord): boolean {
  const immutableKeys = [
    'fighter1',
    'fighter2',
    'creatorId',
    'opponentId',
    'votes1',
    'votes2',
    'winner',
    'finishedAt',
    'status',
  ];

  for (const key of immutableKeys) {
    if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) {
      return true;
    }
  }

  return false;
}

export function assertDebateInvariants(data: DebateRecord): void {
  const status = asString(data['status']) || 'waiting';
  const fighter1 = asString(data['fighter1']) || asString(data['creatorId']);
  const fighter2 = asString(data['fighter2']) || asString(data['opponentId']);
  const activeSpeakerId = asString(data['activeSpeakerId']);
  const totalRounds = asInt(data['totalRounds'], 3);
  const roundIndex = readRoundIndex(data);

  if (status === 'active') {
    if (!fighter1 || !fighter2 || fighter1 === fighter2) {
      throw new HttpsError(
        'failed-precondition',
        'Active debate must have two distinct fighters.',
        { reason: 'INVARIANT_ACTIVE_TWO_FIGHTERS_REQUIRED' },
      );
    }

    if (!activeSpeakerId || (activeSpeakerId !== fighter1 && activeSpeakerId !== fighter2)) {
      throw new HttpsError(
        'failed-precondition',
        'Active speaker must match one of fighters.',
        { reason: 'INVARIANT_ACTIVE_SPEAKER_INVALID' },
      );
    }
  }

  if (roundIndex < 1 || totalRounds < 1 || roundIndex > totalRounds) {
    throw new HttpsError(
      'failed-precondition',
      'Round index is outside allowed range.',
      { reason: 'INVARIANT_ROUND_RANGE_INVALID' },
    );
  }
}

export function assertTransitionInvariants(
  before: DebateRecord,
  after: DebateRecord,
): void {
  const beforeStatus = asString(before['status']) || 'waiting';

  if (beforeStatus === 'finished' && hasFinishedImmutableMutation(before, after)) {
    throw new HttpsError(
      'failed-precondition',
      'Finished debate is immutable in normal flow.',
      { reason: 'INVARIANT_FINISHED_IMMUTABLE' },
    );
  }

  assertDebateInvariants(after);
}

function hasRealOpponentId(fighter1: string, fighter2: string): boolean {
  const f2 = fighter2.trim();
  if (!f2) return false;
  if (f2 === fighter1.trim()) return false;
  return !LEGACY_OPPONENT_ID_PLACEHOLDERS.has(f2.toLowerCase());
}

export function evaluateAcceptGuard(params: {
  uid: string;
  status: string;
  fighter1: string;
  fighter2: string;
  invitedUserId: string;
  opponentId: string;
  creationMode: string;
  strictTransitionsEnabled: boolean;
}): { noop: boolean } {
  const {
    uid,
    status,
    fighter1,
    fighter2,
    invitedUserId,
    opponentId,
    creationMode,
    strictTransitionsEnabled,
  } = params;

  if (status === 'finished') {
    throw new HttpsError('failed-precondition', 'Дебат уже завершён.', {
      reason: 'ACCEPT_ALREADY_FINISHED',
    });
  }

  const hasReservedOpponent = hasRealOpponentId(fighter1, fighter2);
  const reservedInviteUid = invitedUserId
    || (creationMode === 'direct_invite' ? (opponentId || fighter2) : '');
  const inviteBased = creationMode === 'direct_invite' || reservedInviteUid !== '';

  if (inviteBased) {
    if (!reservedInviteUid || uid !== reservedInviteUid) {
      throw new HttpsError(
        'permission-denied',
        'Только приглашённый пользователь может принять вызов.',
        { reason: 'ACCEPT_NOT_INVITED_USER' },
      );
    }
  } else if (hasReservedOpponent && fighter2 !== uid) {
    throw new HttpsError('already-exists', 'У дебата уже есть другой оппонент.', {
      reason: 'ACCEPT_OPPONENT_ALREADY_SET',
    });
  }

  if (uid === fighter1) {
    throw new HttpsError('invalid-argument', 'Нельзя принять собственный вызов.', {
      reason: 'ACCEPT_SELF_CHALLENGE',
    });
  }

  if (status === 'active') {
    if (fighter2 === uid) {
      return { noop: true };
    }

    throw new HttpsError('already-exists', 'У дебата уже есть другой оппонент.', {
      reason: 'ACCEPT_OPPONENT_ALREADY_SET',
    });
  }

  if (status !== 'waiting') {
    if (strictTransitionsEnabled) {
      throw new HttpsError(
        'failed-precondition',
        'Strict transition policy forbids accept in current status.',
        { reason: 'ACCEPT_STATUS_INVALID' },
      );
    }

    throw new HttpsError('failed-precondition', 'Дебат нельзя принять в текущем статусе.', {
      reason: 'ACCEPT_STATUS_INVALID',
    });
  }

  return { noop: false };
}

export function assertCanSendMessage(params: {
  uid: string;
  debate: DebateRecord;
  hasReadAccess: boolean;
  status: string;
  isPlayableStatus: boolean;
}): { roundIndex: number } {
  const { uid, debate, hasReadAccess, status, isPlayableStatus } = params;

  if (!hasReadAccess) {
    throw new HttpsError('permission-denied', 'Нет доступа к этому дебату.', {
      reason: 'MESSAGE_ACCESS_DENIED',
    });
  }

  if (status === 'finished') {
    throw new HttpsError('failed-precondition', 'Дебат уже завершён.', {
      reason: 'MESSAGE_DEBATE_FINISHED',
    });
  }

  if (status === 'waiting' || status === 'cancelled') {
    throw new HttpsError('failed-precondition', 'Дебат ещё не начат или отменён.', {
      reason: 'MESSAGE_DEBATE_NOT_LIVE',
    });
  }

  if (!isPlayableStatus) {
    throw new HttpsError('failed-precondition', 'Сообщения недоступны в текущем статусе дебата.', {
      reason: 'MESSAGE_BAD_STATUS',
    });
  }

  const fighter1 = asString(debate['fighter1']) || asString(debate['creatorId']);
  const fighter2 = asString(debate['fighter2']) || asString(debate['opponentId']);
  if (uid !== fighter1 && uid !== fighter2) {
    throw new HttpsError('permission-denied', 'Только бойцы могут писать.', {
      reason: 'TURN_NOT_FIGHTER',
    });
  }

  const activeSpeakerId = asString(debate['activeSpeakerId']);
  if (activeSpeakerId && uid !== activeSpeakerId) {
    throw new HttpsError('failed-precondition', 'Сейчас не ваш ход.', {
      reason: 'TURN_NOT_ACTIVE_SPEAKER',
    });
  }

  const roundEndsAtGuard = debate['roundEndsAt'];
  if (
    roundEndsAtGuard
    && typeof roundEndsAtGuard === 'object'
    && 'toDate' in roundEndsAtGuard
    && typeof (roundEndsAtGuard as { toDate: unknown }).toDate === 'function'
    && activeSpeakerId
    && uid === activeSpeakerId
  ) {
    const endMs = ((roundEndsAtGuard as { toDate: () => Date }).toDate()).getTime();
    if (Date.now() > endMs) {
      throw new HttpsError('failed-precondition', 'Время хода истекло.', {
        reason: 'TURN_TIME_EXPIRED',
      });
    }
  }

  const isRoundActive =
    typeof debate['isRoundActive'] === 'boolean' ? debate['isRoundActive'] as boolean : true;
  if (!isRoundActive) {
    throw new HttpsError('failed-precondition', 'Раунд не активен.', {
      reason: 'ROUND_NOT_ACTIVE',
    });
  }

  return {
    roundIndex: readRoundIndex(debate),
  };
}

export function assertCanCastVote(params: {
  uid: string;
  debate: DebateRecord;
  hasReadAccess: boolean;
  status: string;
  isPlayableStatus: boolean;
}): { roundIndex: number } {
  const { uid, debate, hasReadAccess, status, isPlayableStatus } = params;

  if (!hasReadAccess) {
    throw new HttpsError('permission-denied', 'Доступ к дебату ограничен.', {
      reason: 'VOTE_ACCESS_DENIED',
    });
  }

  if (status === 'finished') {
    throw new HttpsError('failed-precondition', 'Дебат уже завершён.', {
      reason: 'VOTE_DEBATE_FINISHED',
    });
  }

  if (!isPlayableStatus) {
    throw new HttpsError('failed-precondition', 'Голосование доступно только во время активного дебата.', {
      reason: 'VOTE_DEBATE_NOT_LIVE',
    });
  }

  const fighter1 = asString(debate['fighter1']) || asString(debate['creatorId']);
  const fighter2 = asString(debate['fighter2']) || asString(debate['opponentId']);
  if (uid === fighter1 || uid === fighter2) {
    throw new HttpsError('permission-denied', 'Бойцы не могут голосовать.', {
      reason: 'VOTE_FIGHTER_FORBIDDEN',
    });
  }

  return {
    roundIndex: readRoundIndex(debate),
  };
}

export function assertCanFinishDebate(params: {
  debate: DebateRecord;
  status: string;
}): void {
  const { debate, status } = params;

  if (status !== 'active') {
    throw new HttpsError('failed-precondition', 'Завершение доступно только для активного дебата.', {
      reason: 'FINISH_STATUS_INVALID',
    });
  }

  const fighter1 = asString(debate['fighter1']) || asString(debate['creatorId']);
  const fighter2 = asString(debate['fighter2']) || asString(debate['opponentId']);
  if (!fighter1 || !fighter2 || fighter1 === fighter2) {
    throw new HttpsError('failed-precondition', 'Нельзя завершить дебат без валидной пары бойцов.', {
      reason: 'FINISH_INVALID_FIGHTERS',
    });
  }
}

export function assertCanAdvanceOrFinish(params: {
  uid: string;
  debate: DebateRecord;
}): void {
  const { uid, debate } = params;
  const creatorId = asString(debate['creatorId']);
  const opponentId = asString(debate['opponentId']);
  const fighter1 = asString(debate['fighter1']) || creatorId;
  const fighter2 = asString(debate['fighter2']) || opponentId;

  if (uid !== fighter1 && uid !== fighter2 && uid !== creatorId && uid !== opponentId) {
    throw new HttpsError('permission-denied', 'Только участники дебата могут запускать advance.', {
      reason: 'ADVANCE_NOT_PARTICIPANT',
    });
  }
}

export function assertCanCancelDebate(params: {
  uid: string;
  creatorId: string;
  status: string;
}): void {
  const { uid, creatorId, status } = params;

  if (creatorId !== uid) {
    throw new HttpsError('permission-denied', 'Только создатель может отменить вызов.', {
      reason: 'CANCEL_NOT_CREATOR',
    });
  }

  if (status !== 'waiting') {
    throw new HttpsError('failed-precondition', 'Отмена доступна только до старта дебата.', {
      reason: 'CANCEL_STATUS_INVALID',
    });
  }
}

export function assertCanCreateDebate(params: {
  uid: string;
  topic: string;
  durationSeconds: number;
  totalRounds: number;
  creationMode: string;
  visibilityMode: string;
  languageCode: string;
  region: string;
  invitedUserId: string;
  allowedCreationModes: readonly string[];
  allowedVisibilityModes: readonly string[];
  allowedLanguages: readonly string[];
  allowedRegions: readonly string[];
  allowedDurations: readonly number[];
  allowedRounds: readonly number[];
}): void {
  const {
    uid,
    topic,
    durationSeconds,
    totalRounds,
    creationMode,
    visibilityMode,
    languageCode,
    region,
    invitedUserId,
    allowedCreationModes,
    allowedVisibilityModes,
    allowedLanguages,
    allowedRegions,
    allowedDurations,
    allowedRounds,
  } = params;

  if (!topic || topic.length < 3) {
    throw new HttpsError('invalid-argument', 'Тема должна быть не короче 3 символов.', {
      reason: 'CREATE_TOPIC_INVALID',
    });
  }
  if (!allowedCreationModes.includes(creationMode)) {
    throw new HttpsError('invalid-argument', 'Некорректный creationMode.', {
      reason: 'CREATE_MODE_INVALID',
    });
  }
  if (!allowedVisibilityModes.includes(visibilityMode)) {
    throw new HttpsError('invalid-argument', 'Некорректный visibilityMode.', {
      reason: 'CREATE_VISIBILITY_INVALID',
    });
  }
  if (!allowedLanguages.includes(languageCode)) {
    throw new HttpsError('invalid-argument', 'Некорректный languageCode.', {
      reason: 'CREATE_LANGUAGE_INVALID',
    });
  }
  if (!allowedRegions.includes(region)) {
    throw new HttpsError('invalid-argument', 'Некорректный region.', {
      reason: 'CREATE_REGION_INVALID',
    });
  }
  if (!allowedDurations.includes(durationSeconds)) {
    throw new HttpsError('invalid-argument', 'Некорректная длительность раунда.', {
      reason: 'CREATE_DURATION_INVALID',
    });
  }
  if (!allowedRounds.includes(totalRounds)) {
    throw new HttpsError('invalid-argument', 'Некорректное число раундов.', {
      reason: 'CREATE_ROUNDS_INVALID',
    });
  }

  if (creationMode === 'direct_invite' && !invitedUserId) {
    throw new HttpsError('invalid-argument', 'Для direct_invite требуется invitedUserId.', {
      reason: 'CREATE_INVITED_REQUIRED',
    });
  }
  if (invitedUserId && invitedUserId === uid) {
    throw new HttpsError('invalid-argument', 'Нельзя пригласить самого себя.', {
      reason: 'CREATE_SELF_INVITE',
    });
  }
  if (visibilityMode === 'private' && !invitedUserId) {
    throw new HttpsError('invalid-argument', 'Private дебат требует invitedUserId.', {
      reason: 'CREATE_PRIVATE_INVITED_REQUIRED',
    });
  }
}
