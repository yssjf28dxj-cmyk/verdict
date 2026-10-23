import * as firestore from 'firebase-admin/firestore';

export const ALLOWED_DURATIONS = [30, 60, 90, 120, 180, 300, 420, 600] as const;
export const ALLOWED_ROUNDS = [1, 3, 5] as const;
export const TERMS_POLICY_VERSION = 'v1_mean_nearest_strict';

type WaitingInput = {
  uid: string; name: string; rating: number; topic: string;
  durationSeconds: number; totalRounds: number; creationMode: string;
  visibilityMode: string; languageCode: string; region: string;
  invitedUserId: string; preciseDeadlines: boolean; strictTransitions: boolean;
};

// Explicit fresh schema shared by ordinary challenges and rematches. Never
// spread an earlier battle: votes, results, messages and clock state stay there.
export function buildWaitingDebate(input: WaitingInput): firestore.DocumentData {
  const { uid, name, rating, topic, durationSeconds, totalRounds,
    creationMode, visibilityMode, languageCode, region, invitedUserId } = input;
  return {
    topic, creatorId: uid, fighter1: uid, fighter1Name: name, fighter1Rating: rating,
    fighter2: invitedUserId || '', fighter2Name: '', fighter2Rating: 0,
    invitedUserId: invitedUserId || '', status: 'waiting', durationSeconds,
    roundDurationSeconds: durationSeconds, totalRounds,
    termsProposalCreator: { uid, roundDurationSeconds: durationSeconds, totalRounds,
      submittedAt: firestore.FieldValue.serverTimestamp() },
    termsResolved: { roundDurationSeconds: durationSeconds, totalRounds,
      policyVersion: TERMS_POLICY_VERSION, resolutionMode: 'initial_creator_defaults',
      resolvedAt: firestore.FieldValue.serverTimestamp() },
    termsResolutionStatus: 'pending_opponent', termsResolverVersion: TERMS_POLICY_VERSION,
    roundIndex: 1, creationMode, visibilityMode, languageCode, region, viewerCount: 0,
    ...(input.preciseDeadlines ? { clockMode: 'bank_v1', timeBankMs: { [uid]: 0 } } : {}),
    votes1: 0, votes2: 0, voteTallyVersion: 1, accessRequests: [],
    accessApprovedUserIds: invitedUserId ? [uid, invitedUserId] : [uid],
    createdAt: firestore.FieldValue.serverTimestamp(), schemaVersion: 2,
    migrationState: 'pre_backfill', normalizerVersion: 'v2_runtime_flags',
    transitionPolicyVersion: input.strictTransitions ? 'strict_v1' : 'compat_v1',
  };
}
