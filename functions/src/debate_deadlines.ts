import { createHash } from 'node:crypto';
import { firestore } from 'firebase-admin';
import { assertCanAdvanceOrFinish } from './domain/debate/guards';

type Data = Record<string, any>;
export type Deadline = { debateId: string; round: number; speaker: string; endMs: number };
type Queue = { enqueue(data: Deadline, options: { id: string; scheduleTime: Date; dispatchDeadlineSeconds: number }): Promise<void> };
const placeholderIds = new Set(['opponent', 'invited', 'fighter', 'оппонент', 'приглашен', 'приглашён']);

// A deadline identifies a specific turn, not just a debate or round.
export function readDeadline(debateId: string, data: Data | undefined): Deadline | null {
  if (!data || !['active', 'live'].includes(data.status) || data.isRoundActive === false) return null;
  const f1 = typeof data.fighter1 === 'string' ? data.fighter1 : '';
  const f2 = typeof data.fighter2 === 'string' ? data.fighter2 : '';
  if (!f1 || !f2 || f1 === f2 || placeholderIds.has(f2.trim().toLowerCase())) return null;
  const endMs = data.roundEndsAt?.toMillis?.();
  const round = data.roundIndex ?? data.currentRound ?? data.round ?? 1;
  const speaker = data.activeSpeakerId || f1;
  if (!Number.isSafeInteger(endMs) || !Number.isInteger(round) || round < 1 || round > 5
    || ![f1, f2].includes(speaker)) return null;
  return { debateId, round, speaker, endMs };
}

export function sameDeadline(a: Deadline | null, b: Deadline | null): boolean {
  return !!a && !!b && a.debateId === b.debateId && a.round === b.round
    && a.speaker === b.speaker && a.endMs === b.endMs;
}

export function deadlineTaskId(deadline: Deadline): string {
  return createHash('sha256').update(JSON.stringify(deadline)).digest('hex');
}

function validPayload(value: unknown): value is Deadline {
  if (!value || typeof value !== 'object') return false;
  const d = value as Deadline;
  return typeof d.debateId === 'string' && d.debateId.length > 0
    && !d.debateId.includes('/') && typeof d.speaker === 'string' && !!d.speaker
    && Number.isInteger(d.round) && d.round >= 1 && d.round <= 5 && Number.isSafeInteger(d.endMs);
}

// Pure clock arithmetic: preserve the scheduled timeline during late delivery.
// Each round contains a turn for each fighter. Pending penalties apply once.
export function planExpiredTurns(debateId: string, data: Data, nowMs: number): Data | null {
  const initial = readDeadline(debateId, data);
  if (!initial || nowMs < initial.endMs) return null;
  const totalRounds = data.totalRounds ?? 3;
  const duration = data.roundDurationSeconds ?? data.durationSeconds ?? data.timeSeconds ?? 60;
  if (![1, 3, 5].includes(totalRounds) || !Number.isFinite(duration) || duration <= 0) {
    throw new Error('Invalid debate timer settings');
  }
  let round = initial.round;
  let speaker = initial.speaker;
  let endMs = initial.endMs;
  const pending: Data = { ...(data.pendingPenalty || {}) };
  for (let transitions = 0; transitions < 10 && nowMs >= endMs; transitions++) {
    if (speaker === data.fighter2) {
      if (round >= totalRounds) return { status: 'finished', isRoundActive: false };
      round++;
      speaker = data.fighter1;
    } else {
      speaker = data.fighter2;
    }
    const penalty = Number.isFinite(pending[speaker]) ? Math.max(0, Math.trunc(pending[speaker])) : 0;
    pending[speaker] = 0;
    endMs += Math.max(duration - penalty, 5) * 1000;
  }
  return {
    roundIndex: round, activeSpeakerId: speaker, isRoundActive: true,
    roundEndsAt: firestore.Timestamp.fromMillis(endMs), pendingPenalty: pending,
  };
}

export function createDeadlineController(db: firestore.Firestore, queue: Queue, clock = Date.now) {
  async function schedule(debateId: string): Promise<void> {
    // Read the latest document: Firestore events may arrive out of order.
    const snapshot = await db.collection('debates').doc(debateId).get();
    const deadline = readDeadline(debateId, snapshot.data());
    if (!deadline) return;
    try {
      await queue.enqueue(deadline, {
        id: deadlineTaskId(deadline),
        scheduleTime: new Date(Math.max(deadline.endMs, clock())),
        dispatchDeadlineSeconds: 60,
      });
    } catch (error) {
      // Deterministic task IDs deduplicate retries of the same Firestore event.
      if ((error as { code?: string }).code !== 'functions/task-already-exists') throw error;
    }
  }

  async function advance(debateId: string, expected?: Deadline, uid?: string): Promise<boolean> {
    const ref = db.collection('debates').doc(debateId);
    return db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const data = snapshot.data();
      if (data && uid) assertCanAdvanceOrFinish({ uid, debate: data });
      const deadline = readDeadline(debateId, data);
      if (!deadline || !data || (expected && !sameDeadline(deadline, expected))) return false;
      const nowMs = clock();
      if (nowMs < deadline.endMs) {
        // Cloud Tasks should not run early. Retry instead of losing the deadline.
        if (expected) throw new Error('Deadline has not arrived');
        return false;
      }
      const patch = planExpiredTurns(debateId, data, nowMs);
      if (!patch) return false;
      if (patch.status === 'finished') {
        // Read votes inside the transaction before writing the final result.
        const votes = await tx.get(ref.collection('votes'));
        let votes1 = 0;
        let votes2 = 0;
        for (const vote of votes.docs) {
          for (const [key, value] of Object.entries(vote.data())) {
            if (key === 'uid' || key === 'updatedAt') continue;
            if (value === 1) votes1++;
            if (value === 2) votes2++;
          }
        }
        Object.assign(patch, {
          votes1, votes2, winner: votes1 > votes2 ? 'fighter1' : votes2 > votes1 ? 'fighter2' : 'draw',
          finishedAt: firestore.FieldValue.serverTimestamp(),
        });
      }
      tx.update(ref, patch);
      return true;
    });
  }

  return {
    schedule,
    advance,
    async onWrite(debateId: string, before: Data | undefined, after: Data | undefined): Promise<void> {
      const next = readDeadline(debateId, after);
      if (next && !sameDeadline(next, readDeadline(debateId, before))) await schedule(debateId);
    },
    async runTask(payload: unknown): Promise<void> {
      if (!validPayload(payload)) throw new Error('Invalid turn deadline task');
      const changed = await advance(payload.debateId, payload);
      console.info('debate.deadline.processed', {
        debateId: payload.debateId, scheduledAtMs: payload.endMs,
        latenessMs: Math.max(0, clock() - payload.endMs), changed,
      });
      // Also enqueue after a duplicate invocation: repairs enqueue failure after commit.
      await schedule(payload.debateId);
    },
  };
}
