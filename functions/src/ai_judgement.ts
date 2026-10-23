import { randomUUID } from 'node:crypto';
import * as firestore from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { validateAiResult } from './domain/debate/ai_result';
import { sanitizeLegacyAiResult } from './private_data_migration';

type Data = Record<string, any>;
export type JudgeInput = { topic: string; fighter1: string; fighter2: string; transcript: string };

// A lease prevents concurrent paid model calls; it is not an exactly-once guarantee
// for the external provider if the process crashes after sending a request.
export function createAiJudgeController(
  db: firestore.Firestore,
  generate?: (input: JudgeInput) => Promise<unknown>,
  clock = Date.now,
) {
  return async (debateId: string, uid: string): Promise<Data> => {
    const ref = db.collection('debates').doc(debateId);
    const privateRef = ref.collection('private_state').doc('judgement');
    const leaseId = randomUUID();
    const claim = await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const result = await tx.get(privateRef);
      if (!snapshot.exists) throw new HttpsError('not-found', 'Дебат не найден.');
      const data = snapshot.data()!;
      const f1 = data.fighter1 || data.creatorId;
      const f2 = data.fighter2 || data.opponentId;
      if (uid !== f1 && uid !== f2) throw new HttpsError('permission-denied', 'Только участники могут запросить вердикт ИИ.', { reason: 'FINALIZE_NOT_PARTICIPANT' });
      if (data.status !== 'finished') throw new HttpsError('failed-precondition', 'Дебат ещё не завершён.', { reason: 'FINALIZE_NOT_FINISHED' });
      if (result.exists) return { existing: result.data()!.aiResult };
      // Preserve legacy content in the protected location before removing its public copy.
      if (data.aiResult) {
        const legacy = sanitizeLegacyAiResult(data.aiResult, data);
        tx.set(privateRef, { aiResult: legacy });
        tx.update(ref, { aiResult: firestore.FieldValue.delete(), aiJudgeLease: firestore.FieldValue.delete() });
        return { existing: legacy };
      }
      if (data.aiJudgeLease?.expiresAt?.toMillis?.() > clock()) {
        throw new HttpsError('aborted', 'Судья уже обрабатывает дебат.', { reason: 'FINALIZE_IN_PROGRESS' });
      }
      tx.update(ref, { aiJudgeLease: { id: leaseId, expiresAt: firestore.Timestamp.fromMillis(clock() + 120000) } });
      return { data, fighter1: String(f1), fighter2: String(f2) };
    });
    if (claim.existing) return { ok: claim.existing.status === 'ready', aiResult: claim.existing };
    const data = claim.data!;
    let aiResult: Data;
    try {
      const messages = await ref.collection('messages').orderBy('createdAt', 'asc').limit(200).get();
      const transcript = messages.docs.map((message) => message.data()).filter((m) =>
        m.messageType === 'text' && [claim.fighter1, claim.fighter2].includes(m.senderId) && typeof m.text === 'string' && m.text.trim(),
      ).map((m) => `[${m.senderId === claim.fighter1 ? 'A' : 'B'}]: ${m.text.trim()}`).join('\n').slice(0, 20000);
      if (!transcript) aiResult = { status: 'insufficient_content', reason: 'no_content', error: true };
      else if (!generate) aiResult = { status: 'unavailable', reason: 'not_configured', error: true };
      else {
        let timer: ReturnType<typeof setTimeout> | undefined;
        try {
          const raw = await Promise.race([
            generate({ topic: String(data.topic || ''), fighter1: claim.fighter1!, fighter2: claim.fighter2!, transcript }),
            new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Judge timed out')), 20000); }),
          ]);
          aiResult = { ...validateAiResult(raw, claim.fighter1!, claim.fighter2!), status: 'ready' };
        } finally { if (timer) clearTimeout(timer); }
      }
    } catch {
      aiResult = { status: 'error', reason: 'unavailable', error: true };
    }
    const committed = await db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if (!current.exists) throw new HttpsError('not-found', 'Дебат удалён.', { reason: 'FINALIZE_NOT_FOUND' });
      if (current.data()!.aiJudgeLease?.id !== leaseId) {
        // A newer lease owns the result. A stale worker must not tell the UI
        // that its result was accepted when it did not commit it.
        const latest = await tx.get(privateRef);
        const existing = latest.data()?.aiResult as Data | undefined;
        if (existing) return existing;
        throw new HttpsError('aborted', 'Вердикт обрабатывается другим запросом.', { reason: 'FINALIZE_IN_PROGRESS' });
      }
      tx.set(privateRef, { aiResult: { ...aiResult, judgedAt: firestore.FieldValue.serverTimestamp() } });
      tx.update(ref, { aiJudgeLease: firestore.FieldValue.delete(), aiResult: firestore.FieldValue.delete() });
      return aiResult;
    });
    // AI is advisory. Authoritative audience results/stats are never changed here.
    return { ok: committed.status === 'ready', aiResult: committed };
  };
}
