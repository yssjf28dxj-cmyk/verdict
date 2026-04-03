import * as admin from 'firebase-admin';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getCoreRuntimeFlags } from './core/runtime_flags';
import { incrementCoreMetric, logCoreEvent } from './core/telemetry';
import {
  assertCanAdvanceOrFinish,
  assertCanCancelDebate,
  assertCanCastVote,
  assertCanCreateDebate,
  assertCanFinishDebate,
  assertCanSendMessage,
  assertTransitionInvariants,
  evaluateAcceptGuard,
} from './domain/debate/guards';

admin.initializeApp();

const db = admin.firestore();
const LEGACY_NAME_PLACEHOLDERS = new Set([
  'guest',
  'google user',
  'fighter',
  'fighter 1',
  'fighter 2',
  'opponent',
  'invited',
  'user',
  'гость',
  'боец',
  'боец 1',
  'боец 2',
  'оппонент',
  'вы',
]);
const LEGACY_OPPONENT_ID_PLACEHOLDERS = new Set([
  'opponent',
  'invited',
  'fighter',
  'оппонент',
  'приглашен',
  'приглашён',
]);
const ALLOWED_DURATIONS = [30, 60, 90, 120, 180, 300, 420, 600] as const;
const ALLOWED_ROUNDS = [1, 3, 5] as const;
const TERMS_POLICY_VERSION = 'v1_mean_nearest_strict';
const MAX_MIGRATION_EMERGENCY_TTL_MS = 24 * 60 * 60 * 1000;
// Grace window (ms) given to in-flight media uploads that started just before
// a round timer expired. Applied in sendDebateMessage (accept late messages),
// advanceRoundOrFinish (delay client-triggered advance), and
// autoAdvanceLiveDebates (delay scheduled advance query threshold).
export const UPLOAD_GRACE_MS = 7_000;
const CANONICAL_DEBATE_STATUSES = ['waiting', 'active', 'finished'] as const;

function asString(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function normalizeName(value: unknown): string {
  const s = asString(value).trim();
  if (!s) return '';
  if (LEGACY_NAME_PLACEHOLDERS.has(s.toLowerCase())) return '';
  return s;
}

function normalizeTopic(value: unknown): string {
  const s = asString(value).trim();
  if (!s) return '';
  const lower = s.toLowerCase();
  if (lower === 'новая дуэль' || lower === 'new duel') return '';
  return s;
}

function deriveNeutralUserName(params: {
  profileName: unknown;
  tokenName: unknown;
  tokenEmail: unknown;
  uid: string;
}): string {
  const profileName = normalizeName(params.profileName);
  if (profileName) return profileName;

  const tokenName = normalizeName(params.tokenName);
  if (tokenName) return tokenName;

  const email = asString(params.tokenEmail).trim();
  if (email) {
    const localPart = normalizeName(email.split('@')[0]);
    if (localPart) return localPart;
  }

  return params.uid;
}

function hasRealOpponentId(fighter1: string, fighter2: string): boolean {
  const f2 = fighter2.trim();
  if (!f2) return false;
  if (f2 === fighter1.trim()) return false;
  return !LEGACY_OPPONENT_ID_PLACEHOLDERS.has(f2.toLowerCase());
}

async function requireAdminOrFounder(request: {
  auth?: { uid?: string; token?: Record<string, unknown> };
}): Promise<void> {
  const uid = request.auth?.uid ?? '';
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.', {
      reason: 'MIGRATION_AUTH_REQUIRED',
    });
  }

  if (request.auth?.token?.admin === true) {
    return;
  }

  const userSnap = await db.collection('users').doc(uid).get();
  const rank = asString(userSnap.data()?.rank).trim();
  if (rank === 'GRANDMASTER') {
    return;
  }

  const accessSnap = await db.collection('admin_runtime').doc('migration_access').get();
  const accessData = accessSnap.data() ?? {};
  const enabled = accessData['enabled'] === true;
  const allowedUids = Array.isArray(accessData['allowedUids'])
    ? accessData['allowedUids'].map((v: unknown) => asString(v)).filter((v: string) => !!v)
    : [];
  const expiresAtRaw = accessData['expiresAt'];
  const expiresAt = expiresAtRaw instanceof admin.firestore.Timestamp
    ? expiresAtRaw
    : null;
  const nowMs = Date.now();
  const expiresAtMs = expiresAt?.toMillis() ?? 0;
  const hasValidExpiry = expiresAtMs > nowMs;
  const withinTtlWindow = hasValidExpiry && expiresAtMs <= nowMs + MAX_MIGRATION_EMERGENCY_TTL_MS;
  const emergencyAllowed =
    enabled &&
    withinTtlWindow &&
    allowedUids.includes(uid);
  if (emergencyAllowed) {
    await db.collection('admin_migration_access_audit').add({
      uid,
      email: asString(request.auth?.token?.email).trim(),
      reason: asString(accessData['reason']).trim(),
      expiresAt,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  throw new HttpsError('permission-denied', 'Only admins can run this operation.', {
    reason: 'MIGRATION_ADMIN_REQUIRED',
  });
}

function clampText(text: string): string {
  const t = text.trim();
  if (t.length > 2000) return t.slice(0, 2000);
  return t;
}

function validateMessageText(text: string): string {
  const t = text.trim();
  if (t.length === 0) {
    throw new HttpsError('invalid-argument', 'Сообщение не может быть пустым.', {
      reason: 'TEXT_EMPTY',
    });
  }
  if (t.length > 2000) {
    throw new HttpsError('invalid-argument', 'Сообщение превышает 2000 символов.', {
      reason: 'TEXT_TOO_LONG',
    });
  }
  return t;
}

function asInt(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

// ─── RATE LIMITER ───────────────────────────────────────────
const rateLimitCache = new Map<string, number>();
const RATE_LIMIT_CLEANUP_INTERVAL = 60_000;
let lastCleanup = Date.now();

function enforceRateLimit(uid: string, action: string, cooldownMs: number): void {
  const now = Date.now();
  // Periodic cleanup to prevent memory leak
  if (now - lastCleanup > RATE_LIMIT_CLEANUP_INTERVAL) {
    const cutoff = now - 120_000;
    for (const [key, ts] of rateLimitCache) {
      if (ts < cutoff) rateLimitCache.delete(key);
    }
    lastCleanup = now;
  }

  const key = `${uid}:${action}`;
  const lastAt = rateLimitCache.get(key) ?? 0;
  if (now - lastAt < cooldownMs) {
    throw new HttpsError('resource-exhausted', 'Слишком частые запросы. Подождите.', {
      reason: 'RATE_LIMIT_EXCEEDED',
      action,
      retryAfterMs: cooldownMs - (now - lastAt),
    });
  }
  rateLimitCache.set(key, now);
}
// ────────────────────────────────────────────────────────────

function sanitizeAllowedInt(
  value: unknown,
  allowed: readonly number[],
  fallback: number,
): number {
  const candidate = asInt(value, fallback);
  return allowed.includes(candidate) ? candidate : fallback;
}

function nearestAllowedStrict(
  raw: number,
  allowed: readonly number[],
): number {
  let best = allowed[0];
  let bestDiff = Math.abs(raw - best);
  for (let i = 1; i < allowed.length; i++) {
    const current = allowed[i];
    const diff = Math.abs(raw - current);
    if (diff < bestDiff) {
      best = current;
      bestDiff = diff;
      continue;
    }
    // Tie-break toward stricter setting (lower value).
    if (diff === bestDiff && current < best) {
      best = current;
    }
  }
  return best;
}

function resolveTerms(params: {
  creatorDurationSeconds: number;
  creatorTotalRounds: number;
  accepterDurationSeconds: number;
  accepterTotalRounds: number;
}): {
  durationSeconds: number;
  totalRounds: number;
} {
  const durationMean =
    (params.creatorDurationSeconds + params.accepterDurationSeconds) / 2;
  const roundsMean =
    (params.creatorTotalRounds + params.accepterTotalRounds) / 2;
  return {
    durationSeconds: nearestAllowedStrict(durationMean, ALLOWED_DURATIONS),
    totalRounds: nearestAllowedStrict(roundsMean, ALLOWED_ROUNDS),
  };
}

function readCreatorTermsProposal(data: Record<string, unknown>): {
  durationSeconds: number;
  totalRounds: number;
} {
  const legacyDuration = sanitizeAllowedInt(
    data.roundDurationSeconds ?? data.durationSeconds,
    ALLOWED_DURATIONS,
    180,
  );
  const legacyRounds = sanitizeAllowedInt(data.totalRounds, ALLOWED_ROUNDS, 3);

  const proposal = data.termsProposalCreator;
  if (!proposal || typeof proposal !== 'object') {
    return {
      durationSeconds: legacyDuration,
      totalRounds: legacyRounds,
    };
  }

  const proposalMap = proposal as Record<string, unknown>;
  return {
    durationSeconds: sanitizeAllowedInt(
      proposalMap.roundDurationSeconds,
      ALLOWED_DURATIONS,
      legacyDuration,
    ),
    totalRounds: sanitizeAllowedInt(
      proposalMap.totalRounds,
      ALLOWED_ROUNDS,
      legacyRounds,
    ),
  };
}

function deriveDebateStyle(params: {
  totalDebates: number;
  wins: number;
  draws: number;
  reputation: number;
  viewerScore: number;
}): string {
  const total = params.totalDebates > 0 ? params.totalDebates : 1;
  const winScore = params.wins + params.draws * 0.5;
  const winRate = winScore / total;

  if (params.reputation <= -10) return 'Volatile';
  if (params.viewerScore >= 40 && params.reputation >= 15) return 'Charismatic';
  if (winRate >= 0.65 && params.reputation >= 5) return 'Dominant';
  if (winRate < 0.4 && params.reputation >= 0) return 'Underdog';
  if (params.reputation >= 10) return 'Composed';
  return 'Balanced';
}

function invitedIds(data: Record<string, unknown>): string[] {
  const raw = data.invitedUserIds;
  if (!Array.isArray(raw)) return [];
  return raw.map((v) => asString(v)).filter((v) => !!v);
}

function normalizeDebateStatus(
  value: unknown,
  fallback: (typeof CANONICAL_DEBATE_STATUSES)[number] = 'waiting',
): (typeof CANONICAL_DEBATE_STATUSES)[number] {
  const raw = asString(value);
  if (!raw) return fallback;
  if (raw === 'live') return 'active';
  if (raw === 'waiting' || raw === 'active' || raw === 'finished') return raw;
  return fallback;
}

function readRoundIndex(data: Record<string, unknown>, fallback = 1): number {
  if (typeof data.roundIndex === 'number') return data.roundIndex;
  if (typeof data.currentRound === 'number') return data.currentRound;
  if (typeof data.round === 'number') return data.round;
  return fallback;
}

function readRoundDurationSeconds(data: Record<string, unknown>, fallback = 60): number {
  if (typeof data.roundDurationSeconds === 'number') return data.roundDurationSeconds;
  if (typeof data.durationSeconds === 'number') return data.durationSeconds;
  if (typeof data.timeSeconds === 'number') return data.timeSeconds;
  return fallback;
}

function hasLegacyWritePayload(data: unknown): boolean {
  if (!data || typeof data !== 'object') return false;
  const map = data as Record<string, unknown>;
  const rawStatus = asString(map['status']).toLowerCase();
  return (
    Object.prototype.hasOwnProperty.call(map, 'timeSeconds')
    || Object.prototype.hasOwnProperty.call(map, 'durationSec')
    || Object.prototype.hasOwnProperty.call(map, 'round')
    || Object.prototype.hasOwnProperty.call(map, 'currentRound')
    || Object.prototype.hasOwnProperty.call(map, 'fighter1')
    || Object.prototype.hasOwnProperty.call(map, 'fighter2')
    || Object.prototype.hasOwnProperty.call(map, 'creatorId')
    || Object.prototype.hasOwnProperty.call(map, 'opponentId')
    || rawStatus === 'live'
  );
}

function approvedIds(data: Record<string, unknown>): string[] {
  const raw = data.accessApprovedUserIds;
  if (!Array.isArray(raw)) return [];
  return raw.map((v) => asString(v)).filter((v) => !!v);
}

function canAccessRequestOnly(uid: string, data: Record<string, unknown>): boolean {
  if (!uid) return false;
  return isDebateParticipant(uid, data) || approvedIds(data).includes(uid);
}

function isDebateParticipant(uid: string, data: Record<string, unknown>): boolean {
  if (!uid) return false;
  const creatorId = asString(data.creatorId);
  const opponentId = asString(data.opponentId);
  const fighter1 = asString(data.fighter1) || creatorId;
  const fighter2 = asString(data.fighter2) || opponentId;
  const creationMode = asString(data.creationMode) || 'public_feed';
  const invitedUserId = asString(data.invitedUserId);
  const reservedInviteUid = invitedUserId
    || (creationMode === 'direct_invite' ? (opponentId || fighter2) : '');
  const invitedUserIds = invitedIds(data);
  return uid === fighter1
    || uid === fighter2
    || uid === creatorId
    || uid === opponentId
    || uid === invitedUserId
    || uid === reservedInviteUid
    || invitedUserIds.includes(uid);
}

function canUserReadDebate(uid: string, data: Record<string, unknown>): boolean {
  const visibilityMode = asString(data.visibilityMode) || 'public';
  const creationMode = asString(data.creationMode) || 'public_feed';
  const participant = isDebateParticipant(uid, data);

  if (visibilityMode === 'private') return participant;
  if (visibilityMode === 'request_only') return canAccessRequestOnly(uid, data);
  if (creationMode === 'direct_invite' && !participant) return false;
  return true;
}

/** Дебат идёт (сообщения/голоса): в данных встречаются и `live`, и `active`. */
function isDebatePlayableStatus(status: string): boolean {
  return normalizeDebateStatus(status, 'waiting') === 'active';
}

/**
 * Reads debates/{id}/votes subcollection once (non-transactionally) and returns
 * total side-1 and side-2 vote counts across all vote keys (round_N and debate).
 * Used only at debate finish time — not during live voting.
 */
async function aggregateVoteCounts(
  debateRef: admin.firestore.DocumentReference,
): Promise<{ votes1: number; votes2: number }> {
  const snap = await debateRef.collection('votes').get();
  let votes1 = 0;
  let votes2 = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    for (const [key, val] of Object.entries(data)) {
      if (key === 'uid' || key === 'updatedAt') continue;
      if (val === 1) votes1++;
      else if (val === 2) votes2++;
    }
  }
  return { votes1, votes2 };
}

export const createDebate = onCall({ invoker: 'public' }, async (request) => {
  const coreFlags = await getCoreRuntimeFlags(db);
  if (!coreFlags.legacyWriteEnabled && hasLegacyWritePayload(request.data)) {
    await incrementCoreMetric(db, 'legacy.write.blocked.count', {
      action: 'createDebate',
    });
    throw new HttpsError('failed-precondition', 'Legacy write payload is disabled.', {
      reason: 'LEGACY_WRITE_DISABLED',
    });
  }

  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'CREATE_AUTH_REQUIRED',
    });
  }

  enforceRateLimit(uid, 'createDebate', 5000); // 1 debate per 5 sec

  const topic = clampText(asString(request.data?.topic));
  const durationSeconds = asInt(request.data?.durationSeconds, 180);
  const totalRounds = asInt(request.data?.totalRounds, 3);
  const creationMode = asString(request.data?.creationMode) || 'public_feed';
  const visibilityMode = asString(request.data?.visibilityMode) || 'public';
  const languageCode = asString(request.data?.languageCode) || 'ru';
  const region = asString(request.data?.region) || 'global';
  const invitedUserId = asString(request.data?.invitedUserId);

  const allowedCreationModes = ['public_feed', 'direct_invite'] as const;
  const allowedVisibilityModes = ['public', 'request_only', 'private'] as const;
  const allowedLanguages = ['ru', 'en', 'ar'] as const;
  const allowedRegions = ['global', 'cis', 'mena', 'europe_africa'] as const;

  assertCanCreateDebate({
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
    allowedDurations: ALLOWED_DURATIONS,
    allowedRounds: ALLOWED_ROUNDS,
  });

  const userDoc = await db.collection('users').doc(uid).get();
  const userData = userDoc.data() ?? {};
  const fighter1Name = deriveNeutralUserName({
    profileName: userData.name,
    tokenName: request.auth?.token?.name,
    tokenEmail: request.auth?.token?.email,
    uid,
  });
  const fighter1Rating = asInt(userData.rating, 0);

  const debateRef = db.collection('debates').doc();
  const accessApprovedUserIds = invitedUserId ? [uid, invitedUserId] : [uid];
  await debateRef.set({
    topic,
    creatorId: uid,
    fighter1: uid,
    fighter1Name,
    fighter1Rating,
    fighter2: invitedUserId || '',
    fighter2Name: '',
    fighter2Rating: 0,
    invitedUserId: invitedUserId || '',
    status: 'waiting',
    durationSeconds,
    roundDurationSeconds: durationSeconds,
    totalRounds,
    termsProposalCreator: {
      uid,
      roundDurationSeconds: durationSeconds,
      totalRounds,
      submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    termsResolved: {
      roundDurationSeconds: durationSeconds,
      totalRounds,
      policyVersion: TERMS_POLICY_VERSION,
      resolutionMode: 'initial_creator_defaults',
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    termsResolutionStatus: 'pending_opponent',
    termsResolverVersion: TERMS_POLICY_VERSION,
    roundIndex: 1,
    creationMode,
    visibilityMode,
    languageCode,
    region,
    viewerCount: 0,
    votes1: 0,
    votes2: 0,
    accessRequests: [],
    accessApprovedUserIds,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    schemaVersion: 2,
    migrationState: 'pre_backfill',
    normalizerVersion: 'v2_runtime_flags',
    transitionPolicyVersion: coreFlags.strictTransitionsEnabled ? 'strict_v1' : 'compat_v1',
  });

  await incrementCoreMetric(db, 'action.create.accepted.count');
  await logCoreEvent(db, 'debate.created', {
    debateId: debateRef.id,
    actorUid: uid,
    status: 'waiting',
    schemaVersion: 2,
  });

  return {
    debateId: debateRef.id,
  };
});

export const acceptDebateInvite = onCall({ invoker: 'public' }, async (request) => {
  const coreFlags = await getCoreRuntimeFlags(db);
  if (!coreFlags.legacyWriteEnabled && hasLegacyWritePayload(request.data)) {
    await incrementCoreMetric(db, 'legacy.write.blocked.count', {
      action: 'acceptDebateInvite',
    });
    throw new HttpsError('failed-precondition', 'Legacy write payload is disabled.', {
      reason: 'LEGACY_WRITE_DISABLED',
    });
  }

  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'ACCEPT_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const requestedDurationSeconds = request.data?.proposedRoundDurationSeconds;
  const requestedTotalRounds = request.data?.proposedTotalRounds;
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ACCEPT_DEBATE_ID_REQUIRED',
    });
  }

  if (
    requestedDurationSeconds !== undefined
    && !(ALLOWED_DURATIONS as readonly number[]).includes(asInt(requestedDurationSeconds, -1))
  ) {
    throw new HttpsError('invalid-argument', 'Некорректная длительность раунда в предложении оппонента.', {
      reason: 'ACCEPT_PROPOSAL_DURATION_INVALID',
    });
  }
  if (
    requestedTotalRounds !== undefined
    && !(ALLOWED_ROUNDS as readonly number[]).includes(asInt(requestedTotalRounds, -1))
  ) {
    throw new HttpsError('invalid-argument', 'Некорректное число раундов в предложении оппонента.', {
      reason: 'ACCEPT_PROPOSAL_ROUNDS_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const termsAuditRef = db.collection('admin_terms_resolution_audit').doc();
  let acceptNoop = false;

  await db.runTransaction(async (tx) => {
    const debateSnap = await tx.get(debateRef);
    if (!debateSnap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'ACCEPT_NOT_FOUND',
      });
    }

    const debate = debateSnap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'waiting');

    const fighter1 = asString(debate.fighter1) || asString(debate.creatorId);
    const fighter2 = asString(debate.fighter2) || asString(debate.opponentId);
    const invitedUserId = asString(debate.invitedUserId);
    const opponentId = asString(debate.opponentId);
    const creationMode = asString(debate.creationMode) || 'public_feed';
    const acceptGuard = evaluateAcceptGuard({
      uid,
      status,
      fighter1,
      fighter2,
      invitedUserId,
      opponentId,
      creationMode,
      strictTransitionsEnabled: coreFlags.strictTransitionsEnabled,
    });
    if (acceptGuard.noop) {
      acceptNoop = true;
      return;
    }

    const userRef = db.collection('users').doc(uid);
    const userSnap = await tx.get(userRef);
    const f2UserData = userSnap.data() ?? {};
    const fighter2Name = deriveNeutralUserName({
      profileName: f2UserData.name,
      tokenName: request.auth?.token?.name,
      tokenEmail: request.auth?.token?.email,
      uid,
    });
    const fighter2Rating = asInt(f2UserData.rating, 0);

    const creatorProposal = readCreatorTermsProposal(debate);
    const accepterDurationSeconds = sanitizeAllowedInt(
      requestedDurationSeconds,
      ALLOWED_DURATIONS,
      creatorProposal.durationSeconds,
    );
    const accepterTotalRounds = sanitizeAllowedInt(
      requestedTotalRounds,
      ALLOWED_ROUNDS,
      creatorProposal.totalRounds,
    );
    const resolved = resolveTerms({
      creatorDurationSeconds: creatorProposal.durationSeconds,
      creatorTotalRounds: creatorProposal.totalRounds,
      accepterDurationSeconds,
      accepterTotalRounds,
    });
    const durationChanged = resolved.durationSeconds !== creatorProposal.durationSeconds
      || resolved.durationSeconds !== accepterDurationSeconds;
    const roundsChanged = resolved.totalRounds !== creatorProposal.totalRounds
      || resolved.totalRounds !== accepterTotalRounds;
    const effective = Math.max(resolved.durationSeconds, 5);

    const acceptPatch: Record<string, unknown> = {
      fighter1,
      fighter2: uid,
      opponentId: uid,
      fighter2Name,
      fighter2Rating,
      status: 'active',
      durationSeconds: resolved.durationSeconds,
      roundDurationSeconds: resolved.durationSeconds,
      totalRounds: resolved.totalRounds,
      termsProposalCreator: {
        uid: asString(debate.creatorId) || fighter1,
        roundDurationSeconds: creatorProposal.durationSeconds,
        totalRounds: creatorProposal.totalRounds,
      },
      termsProposalAccepter: {
        uid,
        roundDurationSeconds: accepterDurationSeconds,
        totalRounds: accepterTotalRounds,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      termsResolved: {
        roundDurationSeconds: resolved.durationSeconds,
        totalRounds: resolved.totalRounds,
        policyVersion: TERMS_POLICY_VERSION,
        resolutionMode: 'system_reconciled',
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      termsResolutionStatus: 'resolved',
      termsResolverVersion: TERMS_POLICY_VERSION,
      isRoundActive: true,
      roundIndex: readRoundIndex(debate, 1),
      activeSpeakerId: asString(debate.activeSpeakerId) || fighter1,
      roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      accessApprovedUserIds: admin.firestore.FieldValue.arrayUnion(uid),
      accessRequests: admin.firestore.FieldValue.arrayRemove(uid),
      schemaVersion: 2,
      migrationState: 'pre_backfill',
      normalizerVersion: 'v2_runtime_flags',
      transitionPolicyVersion: coreFlags.strictTransitionsEnabled ? 'strict_v1' : 'compat_v1',
    };

    if (coreFlags.strictTransitionsEnabled) {
      const nextDebate = {
        ...debate,
        ...acceptPatch,
      } as Record<string, unknown>;
      assertTransitionInvariants(debate as Record<string, unknown>, nextDebate);
    }

    tx.update(debateRef, acceptPatch);

    tx.set(termsAuditRef, {
      debateId,
      statusBeforeAccept: status,
      policyVersion: TERMS_POLICY_VERSION,
      resolutionMode: 'system_reconciled',
      creatorUid: asString(debate.creatorId) || fighter1,
      accepterUid: uid,
      creatorProposal: {
        roundDurationSeconds: creatorProposal.durationSeconds,
        totalRounds: creatorProposal.totalRounds,
      },
      accepterProposal: {
        roundDurationSeconds: accepterDurationSeconds,
        totalRounds: accepterTotalRounds,
      },
      resolved: {
        roundDurationSeconds: resolved.durationSeconds,
        totalRounds: resolved.totalRounds,
      },
      changed: {
        duration: durationChanged,
        rounds: roundsChanged,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  if (acceptNoop) {
    await incrementCoreMetric(db, 'action.accept.noop.count');
    await logCoreEvent(db, 'debate.accept.noop', {
      debateId,
      actorUid: uid,
      status: 'active',
    });
    return {
      ok: true,
      policyVersion: TERMS_POLICY_VERSION,
      noop: true,
    };
  }

  await incrementCoreMetric(db, 'action.accept.accepted.count');
  await logCoreEvent(db, 'debate.accepted', {
    debateId,
    actorUid: uid,
    nextStatus: 'active',
    schemaVersion: 2,
    strictTransitions: coreFlags.strictTransitionsEnabled,
  });

  return {
    ok: true,
    policyVersion: TERMS_POLICY_VERSION,
  };
});

export const requestDebateAccess = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'ACCESS_REQUEST_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ACCESS_REQUEST_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'ACCESS_REQUEST_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    if (asString(debate.visibilityMode) !== 'request_only') {
      throw new HttpsError('failed-precondition', 'Этот дебат не требует заявки на доступ.', {
        reason: 'ACCESS_REQUEST_NOT_REQUIRED',
      });
    }
    if (asString(debate.status) === 'finished') {
      throw new HttpsError('failed-precondition', 'Дебат завершён.', {
        reason: 'ACCESS_REQUEST_DEBATE_FINISHED',
      });
    }
    if (canAccessRequestOnly(uid, debate)) {
      throw new HttpsError('failed-precondition', 'У вас уже есть доступ к дебату.', {
        reason: 'ACCESS_REQUEST_ALREADY_GRANTED',
      });
    }

    const requests = Array.isArray(debate.accessRequests)
      ? debate.accessRequests.map((v: unknown) => asString(v)).filter((v: string) => !!v)
      : [];
    if (requests.includes(uid)) {
      throw new HttpsError('already-exists', 'Запрос уже отправлен.', {
        reason: 'ACCESS_REQUEST_ALREADY_SENT',
      });
    }

    tx.update(debateRef, {
      accessRequests: admin.firestore.FieldValue.arrayUnion(uid),
    });
  });

  return { ok: true };
});

export const cancelDebateChallenge = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'CANCEL_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'CANCEL_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'CANCEL_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = asString(debate.status) || 'waiting';
    assertCanCancelDebate({
      uid,
      creatorId: asString(debate.creatorId),
      status,
    });

    tx.delete(debateRef);
  });

  return { ok: true };
});

export const adminDeleteDebate = onCall({ invoker: 'public' }, async (request) => {
  await requireAdminOrFounder(request);

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ADMIN_DELETE_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const debateSnap = await debateRef.get();
  if (!debateSnap.exists) {
    throw new HttpsError('not-found', 'Дебат не найден.', {
      reason: 'ADMIN_DELETE_NOT_FOUND',
    });
  }

  while (true) {
    const messagesSnap = await debateRef.collection('messages').limit(200).get();
    if (messagesSnap.empty) {
      break;
    }

    const batch = db.batch();
    for (const doc of messagesSnap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  await debateRef.delete();

  await logCoreEvent(db, 'debate.admin_deleted', {
    debateId,
    actorUid: request.auth?.uid ?? '',
  });

  return { ok: true };
});

export const adminBanUser = onCall({ invoker: 'public' }, async (request) => {
  await requireAdminOrFounder(request);

  const userId = asString(request.data?.userId);
  if (!userId) {
    throw new HttpsError('invalid-argument', 'userId обязателен.', {
      reason: 'BAN_USER_ID_REQUIRED',
    });
  }

  await db.collection('users').doc(userId).update({
    isBanned: true,
    rank: 'BANNED',
    bannedAt: admin.firestore.FieldValue.serverTimestamp(),
    bannedBy: request.auth?.uid ?? '',
  });

  await logCoreEvent(db, 'user.banned', {
    targetUid: userId,
    actorUid: request.auth?.uid ?? '',
  });

  return { ok: true };
});

export const adminClearWorldChat = onCall({ invoker: 'public' }, async (request) => {
  await requireAdminOrFounder(request);

  let deleted = 0;
  while (true) {
    const snap = await db.collection('world_messages').limit(200).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += snap.docs.length;
  }

  await logCoreEvent(db, 'world_chat.cleared', {
    actorUid: request.auth?.uid ?? '',
    deletedCount: deleted,
  });

  return { ok: true, deleted };
});

export const moderateAccessRequest = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'MODERATE_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const targetUid = asString(request.data?.targetUid);
  const action = asString(request.data?.action);

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'MODERATE_DEBATE_ID_REQUIRED',
    });
  }
  if (!targetUid) {
    throw new HttpsError('invalid-argument', 'targetUid обязателен.', {
      reason: 'MODERATE_TARGET_UID_REQUIRED',
    });
  }
  if (action !== 'approve' && action !== 'reject') {
    throw new HttpsError('invalid-argument', 'action должен быть approve или reject.', {
      reason: 'MODERATE_ACTION_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'MODERATE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    if (asString(debate.visibilityMode) !== 'request_only') {
      throw new HttpsError('failed-precondition', 'Модерация заявок доступна только для request_only дебатов.', {
        reason: 'MODERATE_NOT_REQUEST_ONLY',
      });
    }
    if (asString(debate.creatorId) !== uid) {
      throw new HttpsError('permission-denied', 'Только создатель может модерировать заявки.', {
        reason: 'MODERATE_NOT_CREATOR',
      });
    }
    if (asString(debate.status) === 'finished') {
      throw new HttpsError('failed-precondition', 'Дебат завершён.', {
        reason: 'MODERATE_DEBATE_FINISHED',
      });
    }

    const requests = Array.isArray(debate.accessRequests)
      ? debate.accessRequests.map((v: unknown) => asString(v)).filter((v: string) => !!v)
      : [];

    if (!requests.includes(targetUid)) {
      throw new HttpsError('failed-precondition', 'Заявка пользователя не найдена.', {
        reason: 'MODERATE_REQUEST_NOT_FOUND',
      });
    }

    if (action === 'approve') {
      tx.update(debateRef, {
        accessApprovedUserIds: admin.firestore.FieldValue.arrayUnion(targetUid),
        accessRequests: admin.firestore.FieldValue.arrayRemove(targetUid),
      });
      return;
    }

    tx.update(debateRef, {
      accessRequests: admin.firestore.FieldValue.arrayRemove(targetUid),
    });
  });

  return { ok: true };
});

export const sendDebateMessage = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'MESSAGE_AUTH_REQUIRED',
    });
  }

  enforceRateLimit(uid, 'sendDebateMessage', 2000); // 1 msg per 2 sec

  const debateId = asString(request.data?.debateId);
  const rawText = asString(request.data?.text);
  const messageType = asString(request.data?.messageType) || 'text';
  const mediaUrl = asString(request.data?.mediaUrl) || '';
  const mediaDuration = typeof request.data?.mediaDuration === 'number'
    ? Math.min(Math.max(0, request.data.mediaDuration), 300)
    : 0;

  // Validate messageType
  const validTypes = ['text', 'voice', 'image'];
  if (!validTypes.includes(messageType)) {
    throw new HttpsError('invalid-argument', 'Неверный тип сообщения.', {
      reason: 'MESSAGE_INVALID_TYPE',
    });
  }

  // For text messages, validate text content
  const text = messageType === 'text' ? validateMessageText(rawText) : (rawText || '').trim();

  // For media messages, mediaUrl is required
  if ((messageType === 'voice' || messageType === 'image') && !mediaUrl) {
    throw new HttpsError('invalid-argument', 'mediaUrl обязателен для медиа-сообщений.', {
      reason: 'MESSAGE_MEDIA_URL_REQUIRED',
    });
  }

  // Validate mediaUrl format (must be Firebase Storage URL)
  if (mediaUrl && !mediaUrl.startsWith('https://firebasestorage.googleapis.com/')) {
    throw new HttpsError('invalid-argument', 'Некорректный mediaUrl.', {
      reason: 'MESSAGE_INVALID_MEDIA_URL',
    });
  }

  // Resolve sender name from Firestore, not from client
  const userDoc = await db.collection('users').doc(uid).get();
  const senderName = deriveNeutralUserName({
    profileName: userDoc.data()?.name,
    tokenName: request.auth?.token?.name,
    tokenEmail: request.auth?.token?.email,
    uid,
  });

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'MESSAGE_DEBATE_ID_REQUIRED',
    });
  }
  if (messageType === 'text' && !text) {
    throw new HttpsError('invalid-argument', 'Текст сообщения пуст.', {
      reason: 'MESSAGE_TEXT_EMPTY',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const messageRef = debateRef.collection('messages').doc();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'MESSAGE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'active');
    const guard = assertCanSendMessage({
      uid,
      debate: debate as Record<string, unknown>,
      hasReadAccess: canUserReadDebate(uid, debate),
      status,
      isPlayableStatus: isDebatePlayableStatus(status),
      uploadGraceMs: UPLOAD_GRACE_MS,
    });
    const roundIndex = guard.roundIndex;

    // Build message document based on type
    const messageData: Record<string, unknown> = {
      text: text || '',
      messageType,
      senderId: uid,
      senderName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      roundIndex,
    };

    if (mediaUrl) {
      messageData.mediaUrl = mediaUrl;
    }
    if (messageType === 'voice' && mediaDuration > 0) {
      messageData.mediaDuration = mediaDuration;
    }

    tx.set(messageRef, messageData);
  });

  return { ok: true, messageId: messageRef.id };
});

// ─── AI JUDGE ────────────────────────────────────────────────────────────────
// Reads all text messages from the finished debate, sends them to Gemini,
// and writes a structured AI verdict to debates/{debateId}.aiResult.
// Safe to call only once — re-calls are rejected with FINALIZE_ALREADY_JUDGED.
export const finalizeBattle = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'FINALIZE_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'FINALIZE_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const snap = await debateRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Дебат не найден.', {
      reason: 'FINALIZE_NOT_FOUND',
    });
  }

  const debate = snap.data() ?? {};

  // Only participants may trigger AI judging.
  const fighter1 = asString(debate['fighter1']) || asString(debate['creatorId']);
  const fighter2 = asString(debate['fighter2']) || asString(debate['opponentId']);
  if (uid !== fighter1 && uid !== fighter2) {
    throw new HttpsError('permission-denied', 'Только участники могут запросить вердикт ИИ.', {
      reason: 'FINALIZE_NOT_PARTICIPANT',
    });
  }

  // Guard: debate must be finished before judging.
  const status = normalizeDebateStatus(debate['status'], 'active');
  if (status !== 'finished') {
    throw new HttpsError('failed-precondition', 'Дебат ещё не завершён.', {
      reason: 'FINALIZE_NOT_FINISHED',
    });
  }

  // Guard: idempotency — prevent duplicate AI calls.
  if (debate['aiResult'] != null) {
    throw new HttpsError('already-exists', 'ИИ-вердикт уже вынесен.', {
      reason: 'FINALIZE_ALREADY_JUDGED',
    });
  }

  // Read names for the prompt.
  const topic = asString(debate['topic']) || 'Неизвестная тема';
  const fighter1Name = asString(debate['fighter1Name']) || 'Боец A';
  const fighter2Name = asString(debate['fighter2Name']) || 'Боец Б';

  // Fetch up to 200 text messages, ordered by creation time.
  const msgSnap = await debateRef
    .collection('messages')
    .orderBy('createdAt', 'asc')
    .limit(200)
    .get();

  // Build message log — skip voice/image (no transcript available).
  const lines: string[] = [];
  for (const doc of msgSnap.docs) {
    const m = doc.data();
    if (asString(m['messageType']) !== 'text') continue;
    const text = asString(m['text']).trim();
    if (!text) continue;
    const senderId = asString(m['senderId']);
    const label = senderId === fighter1 ? fighter1Name : fighter2Name;
    lines.push(`[${label}]: ${text}`);
  }

  if (lines.length === 0) {
    // No text messages → write a "no-content" result rather than crashing.
    await debateRef.update({
      aiResult: {
        winnerId: 'draw',
        winnerKey: 'draw',
        scoreA: 50,
        scoreB: 50,
        reasoning: 'Текстовых аргументов не обнаружено — вердикт не может быть вынесен.',
        judgedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
    return { ok: true, skipped: true };
  }

  // ── Gemini call ──────────────────────────────────────────────
  const apiKey = process.env['GEMINI_API_KEY'] ?? '';
  if (!apiKey) {
    throw new HttpsError('internal', 'Gemini API key не настроен.', {
      reason: 'FINALIZE_NO_API_KEY',
    });
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

  const prompt = `
Ты строгий судья дебатов. Оцени следующий дебат на тему: "${topic}".

Боец A: ${fighter1Name} (ID: ${fighter1})
Боец Б: ${fighter2Name} (ID: ${fighter2})

Переписка дебата:
${lines.join('\n')}

Оцени логику, аргументы и убедительность каждого бойца.
Ответь ТОЛЬКО валидным JSON без markdown-блоков:
{"winnerId":"<UID победителя или строка 'draw'>","winnerKey":"<fighter1|fighter2|draw>","scoreA":<0-100>,"scoreB":<0-100>,"reasoning":"<2-3 предложения на русском>"}
`.trim();

  let aiResult: Record<string, unknown>;
  try {
    const response = await model.generateContent(prompt);
    const raw = response.response.text().trim();
    // Strip accidental markdown fences if Gemini wraps in ```json ... ```
    const jsonStr = raw.replace(/^```[a-z]*\n?/i, '').replace(/\n?```$/,'');
    const parsed = JSON.parse(jsonStr) as {
      winnerId: string;
      winnerKey: string;
      scoreA: number;
      scoreB: number;
      reasoning: string;
    };

    // Clamp scores to valid range.
    aiResult = {
      winnerId: asString(parsed.winnerId) || 'draw',
      winnerKey: asString(parsed.winnerKey) || 'draw',
      scoreA: Math.min(100, Math.max(0, Number(parsed.scoreA) || 50)),
      scoreB: Math.min(100, Math.max(0, Number(parsed.scoreB) || 50)),
      reasoning: asString(parsed.reasoning) || '',
      judgedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
  } catch (err) {
    // On Gemini error or JSON parse failure — write error marker so client
    // can hide the AI card gracefully instead of showing a frozen spinner.
    await debateRef.update({
      aiResult: {
        error: true,
        reason: err instanceof Error ? err.message : 'unknown',
        judgedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
    return { ok: false, error: true };
  }

  await debateRef.update({ aiResult });

  // Increment wins for the AI-determined winner (skip on draw).
  const winnerId = aiResult['winnerId'] as string;
  if (winnerId && winnerId !== 'draw') {
    await admin.firestore().collection('users').doc(winnerId).update({
      wins: admin.firestore.FieldValue.increment(1),
    });
  }

  await logCoreEvent(db, 'debate.ai_judged', {
    debateId,
    actorUid: uid,
    winnerKey: aiResult['winnerKey'],
  });

  return { ok: true };
});

// Allows the active speaker to surrender their remaining time and immediately
// pass control to the opponent. Sets roundEndsAt to the past (beyond the grace
// window) so the next ticker tick triggers advance without delay.
export const yieldTurn = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'YIELD_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'YIELD_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'YIELD_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'active');

    if (status === 'finished') {
      throw new HttpsError('failed-precondition', 'Дебат уже завершён.', {
        reason: 'YIELD_DEBATE_FINISHED',
      });
    }
    if (status !== 'active') {
      throw new HttpsError('failed-precondition', 'Дебат не активен.', {
        reason: 'YIELD_DEBATE_NOT_ACTIVE',
      });
    }

    const isRoundActive =
      typeof debate.isRoundActive === 'boolean' ? debate.isRoundActive : true;
    if (!isRoundActive) {
      throw new HttpsError('failed-precondition', 'Раунд не активен.', {
        reason: 'YIELD_ROUND_NOT_ACTIVE',
      });
    }

    const activeSpeakerId = asString(debate.activeSpeakerId);
    if (!activeSpeakerId) {
      throw new HttpsError('failed-precondition', 'Активный спикер не назначен.', {
        reason: 'YIELD_NO_ACTIVE_SPEAKER',
      });
    }
    if (uid !== activeSpeakerId) {
      throw new HttpsError('permission-denied', 'Только активный спикер может уступить слово.', {
        reason: 'YIELD_NOT_ACTIVE_SPEAKER',
      });
    }

    // Place roundEndsAt firmly in the past — beyond the grace window — so that
    // both the client ticker and autoAdvanceLiveDebates detect expiry on the
    // very next check without waiting for UPLOAD_GRACE_MS to elapse.
    const expiredMs = Date.now() - UPLOAD_GRACE_MS - 100;

    tx.update(debateRef, {
      roundEndsAt: admin.firestore.Timestamp.fromMillis(expiredMs),
      yieldedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

export const sendWorldMessage = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'WORLD_AUTH_REQUIRED',
    });
  }

  enforceRateLimit(uid, 'sendWorldMessage', 3000); // 1 msg per 3 sec

  const rawText = asString(request.data?.text).trim();
  if (!rawText || rawText.length === 0) {
    throw new HttpsError('invalid-argument', 'Сообщение пустое.', {
      reason: 'WORLD_TEXT_EMPTY',
    });
  }
  if (rawText.length > 1000) {
    throw new HttpsError('invalid-argument', 'Сообщение превышает 1000 символов.', {
      reason: 'WORLD_TEXT_TOO_LONG',
    });
  }

  // Check ban
  const userDoc = await db.collection('users').doc(uid).get();
  const userData = userDoc.data() ?? {};
  if (userData.isBanned === true) {
    throw new HttpsError('permission-denied', 'Вы заблокированы.', {
      reason: 'WORLD_USER_BANNED',
    });
  }

  const senderName = deriveNeutralUserName({
    profileName: userData.name,
    tokenName: request.auth?.token?.name,
    tokenEmail: request.auth?.token?.email,
    uid,
  });

  await db.collection('world_messages').add({
    text: rawText,
    senderId: uid,
    senderName,
    senderRating: asInt(userData.rating, 0),
    senderPhotoUrl: asString(userData.avatarUrl),
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true };
});

export const applyPenalty = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'PENALTY_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const seconds = asInt(request.data?.seconds, 0);

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'PENALTY_DEBATE_ID_REQUIRED',
    });
  }
  if (seconds <= 0 || seconds > 30) {
    throw new HttpsError('invalid-argument', 'seconds должен быть 1..30.', {
      reason: 'PENALTY_SECONDS_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'PENALTY_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'active');
    if (status === 'finished') {
      throw new HttpsError('failed-precondition', 'Дебат завершён.', {
        reason: 'PENALTY_DEBATE_FINISHED',
      });
    }
    if (!isDebatePlayableStatus(status)) {
      throw new HttpsError('failed-precondition', 'Штраф недоступен в текущем статусе дебата.', {
        reason: 'PENALTY_DEBATE_NOT_PLAYABLE',
      });
    }

    const isRoundActive = typeof debate.isRoundActive === 'boolean' ? debate.isRoundActive : true;
    if (!isRoundActive) {
      throw new HttpsError('failed-precondition', 'Раунд не активен.', {
        reason: 'ROUND_NOT_ACTIVE',
      });
    }

    const fighter1 = asString(debate.fighter1) || asString(debate.creatorId);
    const fighter2 = asString(debate.fighter2) || asString(debate.opponentId);
    if (uid !== fighter1 && uid !== fighter2) {
      throw new HttpsError('permission-denied', 'Только бойцы могут назначать штраф.', {
        reason: 'TURN_NOT_FIGHTER',
      });
    }

    const activeSpeakerId = asString(debate.activeSpeakerId);
    if (!activeSpeakerId) {
      throw new HttpsError('failed-precondition', 'Сейчас невозможно применить штраф: не назначен активный спикер.', {
        reason: 'TURN_NOT_ASSIGNED',
      });
    }
    if (uid !== activeSpeakerId) {
      throw new HttpsError('failed-precondition', 'Штраф может назначать только активный спикер.', {
        reason: 'TURN_NOT_ACTIVE_SPEAKER',
      });
    }

    const targetId = uid === fighter1 ? fighter2 : fighter1;
    if (!targetId) {
      throw new HttpsError('failed-precondition', 'Нет оппонента.', {
        reason: 'PENALTY_NO_OPPONENT',
      });
    }

    // Rate-limit: не чаще 1 раза в 10 секунд на пользователя.
    const penaltyRateLimits = (typeof debate.penaltyRateLimitAt === 'object' && debate.penaltyRateLimitAt)
      ? debate.penaltyRateLimitAt as Record<string, unknown>
      : {};
    const lastUserPenaltyAt = penaltyRateLimits[uid];
    if (lastUserPenaltyAt && typeof (lastUserPenaltyAt as admin.firestore.Timestamp).toDate === 'function') {
      const lastMs = ((lastUserPenaltyAt as admin.firestore.Timestamp).toDate() as Date).getTime();
      if (Date.now() - lastMs < 10_000) {
        throw new HttpsError('resource-exhausted', 'Штраф можно ставить не чаще чем раз в 10 секунд.', {
          reason: 'PENALTY_RATE_LIMIT',
        });
      }
    }

    const roundDurationSeconds = readRoundDurationSeconds(debate, 60);
    const minTurnSeconds = 5;

    const roundEndsAt = debate.roundEndsAt;

    // Если штрафуем того, кто СЕЙЧАС говорит — режем roundEndsAt сразу.
    if (activeSpeakerId && activeSpeakerId === targetId && roundEndsAt && typeof roundEndsAt.toDate === 'function') {
      const endMs = (roundEndsAt.toDate() as Date).getTime();
      const nowMs = Date.now();

      const proposedEnd = endMs - seconds * 1000;
      const minEnd = nowMs + minTurnSeconds * 1000;
      const newEnd = Math.max(proposedEnd, minEnd);

      tx.update(debateRef, {
        roundEndsAt: admin.firestore.Timestamp.fromMillis(newEnd),
        lastPenaltyAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPenaltyBy: uid,
        lastPenaltySeconds: seconds,
        [`penaltyRateLimitAt.${uid}`]: admin.firestore.FieldValue.serverTimestamp(),
      });

      return;
    }

    // Иначе — копим pendingPenalty для оппонента и применим при старте его хода.
    const pending = (typeof debate.pendingPenalty === 'object' && debate.pendingPenalty) ? debate.pendingPenalty as Record<string, unknown> : {};
    const currentPending = asInt(pending[targetId], 0);
    const nextPending = Math.min(currentPending + seconds, roundDurationSeconds - minTurnSeconds);

    tx.update(debateRef, {
      pendingPenalty: {
        ...pending,
        [targetId]: nextPending,
      },
      lastPenaltyAt: admin.firestore.FieldValue.serverTimestamp(),
      lastPenaltyBy: uid,
      lastPenaltySeconds: seconds,
      [`penaltyRateLimitAt.${uid}`]: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

export const castVote = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'VOTE_AUTH_REQUIRED',
    });
  }

  enforceRateLimit(uid, 'castVote', 3000); // 1 vote per 3 sec

  const debateId = asString(request.data?.debateId);
  const side = asInt(request.data?.side, 0);
  const scope = asString(request.data?.scope) || 'round';

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'VOTE_DEBATE_ID_REQUIRED',
    });
  }
  if (side !== 1 && side !== 2) {
    throw new HttpsError('invalid-argument', 'side должен быть 1 или 2.', {
      reason: 'VOTE_SIDE_INVALID',
    });
  }
  if (scope !== 'round' && scope !== 'debate') {
    throw new HttpsError('invalid-argument', 'scope должен быть round или debate.', {
      reason: 'VOTE_SCOPE_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'VOTE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    const status = normalizeDebateStatus(debate.status, 'active');
    const guard = assertCanCastVote({
      uid,
      debate: debate as Record<string, unknown>,
      hasReadAccess: canUserReadDebate(uid, debate),
      status,
      isPlayableStatus: isDebatePlayableStatus(status),
    });
    const roundIndex = guard.roundIndex;
    const voteKey = scope === 'debate' ? `debate` : `round_${roundIndex}`;
    const voteRef = debateRef.collection('votes').doc(uid);

    const voteSnap = await tx.get(voteRef);
    const existing = voteSnap.exists ? (voteSnap.data() ?? {}) : {};
    const existingForKey = existing[voteKey];
    if (existingForKey === 1 || existingForKey === 2) {
      throw new HttpsError('already-exists', 'Вы уже голосовали.', {
        reason: 'VOTE_ALREADY_CAST',
      });
    }

    // Записываем голос в карту (one doc per user).
    tx.set(voteRef, {
      uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      [voteKey]: side,
    }, { merge: true });


  });
  return { ok: true };
});

export const getMyVoteStatus = onCall({ invoker: 'public' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'VOTE_STATUS_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  const scope = asString(request.data?.scope) || 'round';

  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'VOTE_STATUS_DEBATE_ID_REQUIRED',
    });
  }
  if (scope !== 'round' && scope !== 'debate') {
    throw new HttpsError('invalid-argument', 'scope должен быть round или debate.', {
      reason: 'VOTE_STATUS_SCOPE_INVALID',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);
  const voteRef = debateRef.collection('votes').doc(uid);

  const [debateSnap, voteSnap] = await Promise.all([
    debateRef.get(),
    voteRef.get(),
  ]);

  if (!debateSnap.exists) {
    throw new HttpsError('not-found', 'Дебат не найден.', {
      reason: 'VOTE_STATUS_NOT_FOUND',
    });
  }
  const debate = debateSnap.data() ?? {};
  if (!canUserReadDebate(uid, debate)) {
    throw new HttpsError('permission-denied', 'Доступ к дебату ограничен.', {
      reason: 'VOTE_STATUS_ACCESS_DENIED',
    });
  }

  const roundIndex = readRoundIndex(debate, 1);

  const voteKey = scope === 'debate' ? 'debate' : `round_${roundIndex}`;

  const voteData = voteSnap.exists ? (voteSnap.data() ?? {}) : {};
  const sideRaw = voteData[voteKey];
  const side = (sideRaw === 1 || sideRaw === 2) ? sideRaw : 0;

  return {
    ok: true,
    roundIndex,
    scope,
    hasVoted: side === 1 || side === 2,
    side,
  };
});

export const advanceRoundOrFinish = onCall({ invoker: 'public' }, async (request) => {
  const coreFlags = await getCoreRuntimeFlags(db);
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Требуется авторизация.', {
      reason: 'ADVANCE_AUTH_REQUIRED',
    });
  }

  const debateId = asString(request.data?.debateId);
  if (!debateId) {
    throw new HttpsError('invalid-argument', 'debateId обязателен.', {
      reason: 'ADVANCE_DEBATE_ID_REQUIRED',
    });
  }

  const debateRef = db.collection('debates').doc(debateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(debateRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Дебат не найден.', {
        reason: 'ADVANCE_NOT_FOUND',
      });
    }

    const debate = snap.data() ?? {};
    assertCanAdvanceOrFinish({
      uid,
      debate: debate as Record<string, unknown>,
    });
    const status = normalizeDebateStatus(debate.status, 'active');
    if (status === 'finished') return;

    const updateWithTransitionCheck = (patch: Record<string, unknown>): void => {
      if (coreFlags.strictTransitionsEnabled) {
        const nextDebate = {
          ...debate,
          ...patch,
        } as Record<string, unknown>;
        assertTransitionInvariants(debate as Record<string, unknown>, nextDebate);
      }
      tx.update(debateRef, patch);
    };

    const roundDurationSeconds = readRoundDurationSeconds(debate, 60);

    const roundEndsAt = debate.roundEndsAt;
    if (!roundEndsAt || typeof roundEndsAt.toDate !== 'function') {
      // Если поля нет (старые дебаты) — создаём endAt и выходим.
      updateWithTransitionCheck({
        isRoundActive: true,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + roundDurationSeconds * 1000),
        activeSpeakerId: asString(debate.activeSpeakerId) || asString(debate.fighter1),
        roundIndex: readRoundIndex(debate, 1),
      });
      return;
    }

    const nowMs = Date.now();
    const endMs = (roundEndsAt.toDate() as Date).getTime();
    // Не бросаем ошибку: клиенты/таймеры часто опрашивают advance — no-op без шума в логах.
    // UPLOAD_GRACE_MS: hold off advancing until the grace window has passed so that
    // in-flight media uploads that started just before expiry can still be accepted
    // by sendDebateMessage (which uses the same UPLOAD_GRACE_MS threshold).
    if (nowMs < endMs + UPLOAD_GRACE_MS) {
      return;
    }

    const totalRounds = (typeof debate.totalRounds === 'number' ? debate.totalRounds : 3);
    const currentRound = readRoundIndex(debate, 1);

    const fighter1 = asString(debate.fighter1);
    const fighter2 = asString(debate.fighter2);
    const activeSpeakerId = asString(debate.activeSpeakerId) || fighter1;

    // SOLO / INVALID OPPONENT GUARD:
    // Если fighter2 не задан или это плейсхолдер (например, "Оппонент"),
    // не переключаем ход на несуществующего пользователя — иначе чат “умирает”.
    const hasRealOpponent = hasRealOpponentId(fighter1, fighter2);
    if (!hasRealOpponent) {
      const effective = Math.max(roundDurationSeconds, 5);
      updateWithTransitionCheck({
        isRoundActive: true,
        activeSpeakerId: fighter1,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
      });
      return;
    }

    const pending = (typeof debate.pendingPenalty === 'object' && debate.pendingPenalty) ? debate.pendingPenalty as Record<string, unknown> : {};
    const takePenalty = (who: string): number => {
      if (!who) return 0;
      const p = asInt(pending[who], 0);
      return p > 0 ? p : 0;
    };

    // TURN SWITCH LOGIC (по таймеру):
    // - если говорил fighter1 -> переключаем на fighter2 (тот же раунд)
    // - если говорил fighter2 -> следующий раунд, снова fighter1
    if (activeSpeakerId === fighter1 && fighter2) {
      const penalty = takePenalty(fighter2);
      const effective = Math.max(roundDurationSeconds - penalty, 5);
      updateWithTransitionCheck({
        isRoundActive: true,
        activeSpeakerId: fighter2,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
        pendingPenalty: {
          ...pending,
          [fighter2]: 0,
        },
      });
      return;
    }

    // Закончился ход fighter2 -> следующий раунд или финиш
    if (currentRound < totalRounds) {
      const nextRound = currentRound + 1;
      const penalty = takePenalty(fighter1);
      const effective = Math.max(roundDurationSeconds - penalty, 5);
      updateWithTransitionCheck({
        isRoundActive: true,
        roundIndex: nextRound,
        activeSpeakerId: fighter1,
        roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
        pendingPenalty: {
          ...pending,
          [fighter1]: 0,
        },
      });
      return;
    }

    assertCanFinishDebate({
      debate: debate as Record<string, unknown>,
      status,
    });

    // Aggregate final vote counts from subcollection — debate doc counters are no longer
    // maintained during voting, so we compute them once at finish time.
    const finalCounts = await aggregateVoteCounts(debateRef);
    const votes1 = finalCounts.votes1;
    const votes2 = finalCounts.votes2;
    const winner = votes1 > votes2 ? 'fighter1' : (votes2 > votes1 ? 'fighter2' : 'draw');

    updateWithTransitionCheck({
      isRoundActive: false,
      status: 'finished',
      winner,
      votes1,
      votes2,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

// 1) Инициализация дебата: выставляем roundEndsAt сразу на сервере.
export const initDebateOnCreate = onDocumentCreated(
  'debates/{debateId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() ?? {};

    const status = normalizeDebateStatus(data.status, 'active');
    if (status === 'finished') return;

    const fighter1 = asString(data.fighter1);
    const fighter2 = asString(data.fighter2);
    const roundDurationSeconds = readRoundDurationSeconds(data, 60);

    const patch: Record<string, unknown> = {};

    if (!data.activeSpeakerId) patch.activeSpeakerId = fighter1;
    if (typeof data.isRoundActive !== 'boolean') patch.isRoundActive = true;
    if (typeof data.roundIndex !== 'number') patch.roundIndex = readRoundIndex(data, 1);
    // Статус НЕ меняем здесь. Дебат остаётся 'waiting' до прихода реального оппонента через acceptDebateInvite.
    // if (status === 'waiting' && hasOpponent) patch.status = 'active';

    // Только если ещё не выставлено.
    if (!data.roundEndsAt) {
      patch.roundEndsAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + roundDurationSeconds * 1000,
      );
    }

    // Подготовим pendingPenalty под обоих бойцов (если оба есть).
    if (!data.pendingPenalty) {
      const pending: Record<string, number> = {};
      if (fighter1) pending[fighter1] = 0;
      if (fighter2) pending[fighter2] = 0;
      if (Object.keys(pending).length > 0) patch.pendingPenalty = pending;
    }

    if (Object.keys(patch).length > 0) {
      await snap.ref.update(patch);
    }
  },
);

// 2) Авто-рефери: периодически переключаем ход/раунд, если время вышло.
export const autoAdvanceLiveDebates = onSchedule(
  { schedule: 'every 1 minutes' },
  async () => {
    // Threshold: only pick up debates where the timer AND the grace window have
    // both fully expired. This guarantees in-flight uploads still within
    // UPLOAD_GRACE_MS of roundEndsAt are never prematurely advanced.
    const thresholdMs = Date.now() - UPLOAD_GRACE_MS;
    const threshold = admin.firestore.Timestamp.fromMillis(thresholdMs);

    // Берём только активные дебаты, где roundEndsAt уже прошёл вместе с grace-окном.
    // (Если понадобится — добавим индекс позже.)
    const q = await db
      .collection('debates')
      .where('status', 'in', ['live', 'active'])
      .where('roundEndsAt', '<=', threshold)
      .limit(50)
      .get();

    if (q.empty) return;

    // По одному, чтобы не ловить contention; функция advanceRoundOrFinish уже транзакционная.
    for (const doc of q.docs) {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        const debate = snap.data() ?? {};
        const status = normalizeDebateStatus(debate.status, 'active');
        if (status === 'finished') return;

        // Эмулируем логику advanceRoundOrFinish, но без auth.
        const roundDurationSeconds = readRoundDurationSeconds(debate, 60);

        const roundEndsAt = debate.roundEndsAt;
        if (!roundEndsAt || typeof roundEndsAt.toDate !== 'function') {
          tx.update(doc.ref, {
            isRoundActive: true,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + roundDurationSeconds * 1000),
            activeSpeakerId: asString(debate.activeSpeakerId) || asString(debate.fighter1),
            roundIndex: readRoundIndex(debate, 1),
          });
          return;
        }

        const endMs = (roundEndsAt.toDate() as Date).getTime();
        if (Date.now() < endMs) return;

        const totalRounds = (typeof debate.totalRounds === 'number' ? debate.totalRounds : 3);
        const currentRound = readRoundIndex(debate, 1);

        const fighter1 = asString(debate.fighter1);
        const fighter2 = asString(debate.fighter2);
        const activeSpeakerId = asString(debate.activeSpeakerId) || fighter1;

        const hasRealOpponent = hasRealOpponentId(fighter1, fighter2);
        if (!hasRealOpponent) {
          tx.update(doc.ref, {
            isRoundActive: true,
            activeSpeakerId: fighter1,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + Math.max(roundDurationSeconds, 5) * 1000),
          });
          return;
        }

        const pending = (typeof debate.pendingPenalty === 'object' && debate.pendingPenalty) ? debate.pendingPenalty as Record<string, unknown> : {};
        const takePenalty = (who: string): number => {
          if (!who) return 0;
          const p = asInt(pending[who], 0);
          return p > 0 ? p : 0;
        };

        if (activeSpeakerId === fighter1 && fighter2) {
          const penalty = takePenalty(fighter2);
          const effective = Math.max(roundDurationSeconds - penalty, 5);
          tx.update(doc.ref, {
            isRoundActive: true,
            activeSpeakerId: fighter2,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
            pendingPenalty: {
              ...pending,
              [fighter2]: 0,
            },
          });
          return;
        }

        if (currentRound < totalRounds) {
          const nextRound = currentRound + 1;
          const penalty = takePenalty(fighter1);
          const effective = Math.max(roundDurationSeconds - penalty, 5);
          tx.update(doc.ref, {
            isRoundActive: true,
            roundIndex: nextRound,
            activeSpeakerId: fighter1,
            roundEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() + effective * 1000),
            pendingPenalty: {
              ...pending,
              [fighter1]: 0,
            },
          });
          return;
        }

        // Aggregate final vote counts from subcollection (same pattern as callable path).
        const finalCounts = await aggregateVoteCounts(doc.ref);
        const votes1 = finalCounts.votes1;
        const votes2 = finalCounts.votes2;
        const winner = votes1 > votes2 ? 'fighter1' : (votes2 > votes1 ? 'fighter2' : 'draw');

        tx.update(doc.ref, {
          isRoundActive: false,
          status: 'finished',
          winner,
          votes1,
          votes2,
          finishedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }
  },
);

export const applyDebateResultToProfiles = onDocumentUpdated(
  'debates/{debateId}',
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};

    const beforeStatus = asString(before.status) || '';
    const afterStatus = asString(after.status) || '';
    if (beforeStatus === 'finished' || afterStatus !== 'finished') {
      return;
    }

    const debateRef = event.data?.after.ref;
    if (!debateRef) return;

    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(debateRef);
      if (!freshSnap.exists) return;

      const debate = freshSnap.data() ?? {};
      if (asString(debate.status) !== 'finished') return;
      if (debate.profileStatsApplied === true) return;

      const fighter1 = asString(debate.fighter1);
      const fighter2 = asString(debate.fighter2);
      const winner = asString(debate.winner);
      const votes1 = asInt(debate.votes1, 0);
      const votes2 = asInt(debate.votes2, 0);

      // Mark processed even for invalid/solo debates to avoid endless retries.
      if (!fighter1 || !hasRealOpponentId(fighter1, fighter2)) {
        tx.update(debateRef, {
          profileStatsApplied: true,
          profileStatsAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const f1Ref = db.collection('users').doc(fighter1);
      const f2Ref = db.collection('users').doc(fighter2);
      const [f1Snap, f2Snap] = await Promise.all([
        tx.get(f1Ref),
        tx.get(f2Ref),
      ]);
      const f1Data = f1Snap.data() ?? {};
      const f2Data = f2Snap.data() ?? {};

      const f1Won = winner === 'fighter1';
      const f2Won = winner === 'fighter2';
      const isDraw = winner === 'draw';

      const f1RatingDelta = f1Won ? 12 : (f2Won ? -8 : 2);
      const f2RatingDelta = f2Won ? 12 : (f1Won ? -8 : 2);
      const f1ReputationDelta = f1Won ? 2 : (f2Won ? -1 : 1);
      const f2ReputationDelta = f2Won ? 2 : (f1Won ? -1 : 1);

      // Viewer score is tied to vote performance and kept bounded by moderate increments.
      const f1ViewerDelta = isDraw
        ? 0.5
        : (f1Won ? Math.max(1, votes1 - votes2 + 1) : -1);
      const f2ViewerDelta = isDraw
        ? 0.5
        : (f2Won ? Math.max(1, votes2 - votes1 + 1) : -1);

      const f1NextTotalDebates = asInt(f1Data.totalDebates, 0) + 1;
      const f1NextWins = asInt(f1Data.wins, 0) + (f1Won ? 1 : 0);
      const f1NextDraws = asInt(f1Data.draws, 0) + (isDraw ? 1 : 0);
      const f1NextReputation = asInt(f1Data.reputation, 0) + f1ReputationDelta;
      const f1NextViewerScore = asInt(f1Data.viewerScore, 0) + f1ViewerDelta;
      const f1NextStyle = deriveDebateStyle({
        totalDebates: f1NextTotalDebates,
        wins: f1NextWins,
        draws: f1NextDraws,
        reputation: f1NextReputation,
        viewerScore: f1NextViewerScore,
      });

      const f2NextTotalDebates = asInt(f2Data.totalDebates, 0) + 1;
      const f2NextWins = asInt(f2Data.wins, 0) + (f2Won ? 1 : 0);
      const f2NextDraws = asInt(f2Data.draws, 0) + (isDraw ? 1 : 0);
      const f2NextReputation = asInt(f2Data.reputation, 0) + f2ReputationDelta;
      const f2NextViewerScore = asInt(f2Data.viewerScore, 0) + f2ViewerDelta;
      const f2NextStyle = deriveDebateStyle({
        totalDebates: f2NextTotalDebates,
        wins: f2NextWins,
        draws: f2NextDraws,
        reputation: f2NextReputation,
        viewerScore: f2NextViewerScore,
      });

      tx.set(f1Ref, {
        totalDebates: admin.firestore.FieldValue.increment(1),
        wins: admin.firestore.FieldValue.increment(f1Won ? 1 : 0),
        losses: admin.firestore.FieldValue.increment(f2Won ? 1 : 0),
        draws: admin.firestore.FieldValue.increment(isDraw ? 1 : 0),
        rating: admin.firestore.FieldValue.increment(f1RatingDelta),
        reputation: admin.firestore.FieldValue.increment(f1ReputationDelta),
        viewerScore: admin.firestore.FieldValue.increment(f1ViewerDelta),
        debateStyle: f1NextStyle,
        lastDebateAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      tx.set(f2Ref, {
        totalDebates: admin.firestore.FieldValue.increment(1),
        wins: admin.firestore.FieldValue.increment(f2Won ? 1 : 0),
        losses: admin.firestore.FieldValue.increment(f1Won ? 1 : 0),
        draws: admin.firestore.FieldValue.increment(isDraw ? 1 : 0),
        rating: admin.firestore.FieldValue.increment(f2RatingDelta),
        reputation: admin.firestore.FieldValue.increment(f2ReputationDelta),
        viewerScore: admin.firestore.FieldValue.increment(f2ViewerDelta),
        debateStyle: f2NextStyle,
        lastDebateAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      tx.update(debateRef, {
        profileStatsApplied: true,
        profileStatsAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  },
);

export const migrateLegacyNamePlaceholders = onCall({ invoker: 'public' }, async (request) => {
  await requireAdminOrFounder(request);

  const dryRun = request.data?.dryRun !== false;
  const batchSize = Math.min(
    Math.max(asInt(request.data?.batchSize, 500), 50),
    1000,
  );
  const maxDocsPerCollection = Math.min(
    Math.max(asInt(request.data?.maxDocsPerCollection, 500), 1),
    50000,
  );

  const summary = {
    dryRun,
    maxDocsPerCollection,
    users: { scanned: 0, updated: 0 },
    debates: { scanned: 0, updated: 0 },
    worldMessages: { scanned: 0, updated: 0 },
    debateMessages: { scanned: 0, updated: 0 },
  };
  const actorUid = request.auth?.uid ?? '';
  const actorEmail = asString(request.auth?.token?.email).trim();
  const lockRef = db.collection('admin_runtime').doc('migration_lock');
  const runRef = db.collection('admin_migration_runs').doc();

  await db.runTransaction(async (tx) => {
    const lockSnap = await tx.get(lockRef);
    const lockData = lockSnap.data() ?? {};
    if (lockData['inProgress'] === true) {
      throw new HttpsError('failed-precondition', 'Migration is already running.', {
        reason: 'MIGRATION_ALREADY_RUNNING',
      });
    }

    tx.set(lockRef, {
      inProgress: true,
      actorUid,
      actorEmail,
      dryRun,
      batchSize,
      maxDocsPerCollection,
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(runRef, {
      actorUid,
      actorEmail,
      dryRun,
      batchSize,
      maxDocsPerCollection,
      users: summary.users,
      debates: summary.debates,
      worldMessages: summary.worldMessages,
      debateMessages: summary.debateMessages,
      status: 'in_progress',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: null,
    });
  });

  try {
    async function processCollection(
      buildQuery: (
        lastDoc?: admin.firestore.QueryDocumentSnapshot,
      ) => admin.firestore.Query,
      onDoc: (
        doc: admin.firestore.QueryDocumentSnapshot,
      ) => Promise<void>,
      onScanned: () => void,
    ): Promise<void> {
      let scanned = 0;
      let lastDoc: admin.firestore.QueryDocumentSnapshot | undefined;

      while (scanned < maxDocsPerCollection) {
        const remaining = maxDocsPerCollection - scanned;
        const queryLimit = Math.min(batchSize, remaining);
        const snap = await buildQuery(lastDoc).limit(queryLimit).get();
        if (snap.empty) {
          break;
        }

        for (const doc of snap.docs) {
          await onDoc(doc);
          onScanned();
          scanned += 1;
        }

        lastDoc = snap.docs[snap.docs.length - 1];
        if (snap.docs.length < queryLimit) {
          break;
        }
      }
    }

    await processCollection(
      (lastDoc) => {
        let q = db.collection('users').orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const patch: Record<string, unknown> = {};

        const normalizedName = normalizeName(data.name);
        if (asString(data.name).trim() && !normalizedName) {
          patch.name = '';
        }

        const normalizedDisplayName = normalizeName(data.displayName);
        if (asString(data.displayName).trim() && !normalizedDisplayName) {
          patch.displayName = '';
        }

        if (Object.keys(patch).length > 0) {
          summary.users.updated += 1;
          if (!dryRun) {
            await doc.ref.update(patch);
          }
        }
      },
      () => {
        summary.users.scanned += 1;
      },
    );

    await processCollection(
      (lastDoc) => {
        let q = db.collection('debates').orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const patch: Record<string, unknown> = {};

        const topic = normalizeTopic(data.topic);
        if (asString(data.topic).trim() && !topic) {
          patch.topic = '';
        }

        const fighter1Name = normalizeName(data.fighter1Name);
        if (asString(data.fighter1Name).trim() && !fighter1Name) {
          patch.fighter1Name = '';
        }

        const fighter2Name = normalizeName(data.fighter2Name);
        if (asString(data.fighter2Name).trim() && !fighter2Name) {
          patch.fighter2Name = '';
        }

        const fighter2 = asString(data.fighter2).trim();
        if (fighter2 && LEGACY_OPPONENT_ID_PLACEHOLDERS.has(fighter2.toLowerCase())) {
          patch.fighter2 = '';
        }

        if (Object.keys(patch).length > 0) {
          summary.debates.updated += 1;
          if (!dryRun) {
            await doc.ref.update(patch);
          }
        }
      },
      () => {
        summary.debates.scanned += 1;
      },
    );

    await processCollection(
      (lastDoc) => {
        let q = db.collection('world_messages').orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const normalizedSenderName = normalizeName(data.senderName);
        if (asString(data.senderName).trim() && !normalizedSenderName) {
          summary.worldMessages.updated += 1;
          if (!dryRun) {
            await doc.ref.update({ senderName: '' });
          }
        }
      },
      () => {
        summary.worldMessages.scanned += 1;
      },
    );

    await processCollection(
      (lastDoc) => {
        let q = db
          .collectionGroup('messages')
          .orderBy(admin.firestore.FieldPath.documentId());
        if (lastDoc) {
          q = q.startAfter(lastDoc.id);
        }
        return q;
      },
      async (doc) => {
        const data = doc.data() ?? {};
        const normalizedSenderName = normalizeName(data.senderName);
        if (asString(data.senderName).trim() && !normalizedSenderName) {
          summary.debateMessages.updated += 1;
          if (!dryRun) {
            await doc.ref.update({ senderName: '' });
          }
        }
      },
      () => {
        summary.debateMessages.scanned += 1;
      },
    );

    await runRef.set({
      users: summary.users,
      debates: summary.debates,
      worldMessages: summary.worldMessages,
      debateMessages: summary.debateMessages,
      status: 'completed',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
      ok: true,
      runId: runRef.id,
      ...summary,
    };
  } catch (error) {
    await runRef.set({
      users: summary.users,
      debates: summary.debates,
      worldMessages: summary.worldMessages,
      debateMessages: summary.debateMessages,
      status: 'failed',
      errorMessage: error instanceof Error ? error.message : String(error),
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    throw error;
  } finally {
    await lockRef.set({
      inProgress: false,
      lastActorUid: actorUid,
      lastActorEmail: actorEmail,
      lastDryRun: dryRun,
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
});

