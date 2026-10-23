import { createHash } from 'node:crypto';
import * as firestore from 'firebase-admin/firestore';
import { validateAiResult } from './domain/debate/ai_result';

type Data = Record<string, any>;
// Accept states written by ai_judgement/sanitizeLegacyAiResult, plus historical
// ready results without status. Never normalize/replace an existing private result.
function isUsablePrivateJudgement(document: Data, debate: Data): boolean {
  const value = document.aiResult;
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  if (value.judgedAt !== undefined && !(value.judgedAt instanceof firestore.Timestamp)) return false;
  if (value.status === undefined || value.status === 'ready') {
    if (value.error !== undefined && value.error !== false) return false;
    try {
      validateAiResult(value, debate.fighter1 || debate.creatorId, debate.fighter2 || debate.opponentId);
      return true;
    } catch { return false; }
  }
  return value.error === true && (
    (value.status === 'insufficient_content' && value.reason === 'no_content')
    || (value.status === 'unavailable' && value.reason === 'not_configured')
    || (value.status === 'error' && value.reason === 'unavailable')
  );
}

export type PrivateDataMigrationStats = {
  profilesScanned: number;
  emailsFound: number;
  debatesScanned: number;
  aiResultsFound: number;
  applied: number;
};

export function sanitizeLegacyAiResult(original: unknown, debate: Data): Data {
  const value = original && typeof original === 'object' && !Array.isArray(original) ? original as Data : null;
  if (value && typeof value.reasoning === 'string'
    && value.reasoning.startsWith('Текстовых аргументов не обнаружено')) {
    return { status: 'insufficient_content', reason: 'no_content', error: true };
  }
  // Older provider errors may contain request details or credentials. They are
  // archived exactly, but must never become a user-visible explanation.
  if (!value || value.error || (value.status !== undefined && value.status !== 'ready')) {
    return { status: 'error', reason: 'unavailable', error: true };
  }
  try {
    const valid = validateAiResult(value, debate.fighter1 || debate.creatorId, debate.fighter2 || debate.opponentId);
    return {
      ...valid,
      status: 'ready',
      ...(value.judgedAt instanceof firestore.Timestamp ? { judgedAt: value.judgedAt } : {}),
    };
  } catch {
    return { status: 'error', reason: 'unavailable', error: true };
  }
}

export function createPrivateDataMigrationController(
  db: firestore.Firestore,
  { pageSize = 100 }: { pageSize?: number } = {},
) {
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 500) throw new Error('Invalid migration page size');
  const archive = db.collection('admin_private_data_archive').doc();
  const stats: PrivateDataMigrationStats = {
    profilesScanned: 0, emailsFound: 0, debatesScanned: 0, aiResultsFound: 0, applied: 0,
  };
  let started = false;
  const getStats = (): PrivateDataMigrationStats => ({ ...stats });

  const scan = async (collection: string, visit: (item: firestore.QueryDocumentSnapshot) => Promise<void>) => {
    let cursor: firestore.QueryDocumentSnapshot | undefined;
    while (true) {
      let query = db.collection(collection).orderBy(firestore.FieldPath.documentId()).limit(pageSize);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) return;
      for (const item of page.docs) await visit(item);
      cursor = page.docs[page.docs.length - 1];
    }
  };

  const migrate = async (item: firestore.QueryDocumentSnapshot, kind: 'email' | 'ai'): Promise<void> => {
    const field = kind === 'email' ? 'email' : 'aiResult';
    const recordId = `${kind}_${createHash('sha256').update(item.ref.path).digest('hex')}`;
    const written = await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(item.ref);
      const data = snapshot.data();
      // A concurrent migration or owner may already have removed the field.
      if (!data || !Object.prototype.hasOwnProperty.call(data, field)) return false;
      const privateRef = kind === 'ai' ? item.ref.collection('private_state').doc('judgement') : null;
      const privateSnapshot = privateRef ? await tx.get(privateRef) : null;
      if (privateSnapshot?.exists && !isUsablePrivateJudgement(privateSnapshot.data()!, data)) {
        // Fixed message: neither private payload nor source identifiers enter logs.
        throw new Error('PRIVATE_JUDGEMENT_CONFLICT: migration stopped; existing private judgement requires review');
      }
      tx.create(archive.collection('records').doc(recordId), {
        originalPath: item.ref.path,
        field,
        originalValue: data[field],
        archivedAt: firestore.FieldValue.serverTimestamp(),
      });
      if (privateRef && !privateSnapshot?.exists) {
        tx.set(privateRef, { aiResult: sanitizeLegacyAiResult(data.aiResult, data) });
      }
      tx.update(item.ref, { [field]: firestore.FieldValue.delete() });
      return true;
    });
    if (written) stats.applied++;
  };

  const run = async ({ apply = false }: { apply?: boolean } = {}) => {
    if (started) throw new Error('A migration controller can run only once');
    started = true;
    if (apply) await archive.create({ status: 'running', startedAt: firestore.FieldValue.serverTimestamp() });
    try {
      await scan('users', async (item) => {
        stats.profilesScanned++;
        if (Object.prototype.hasOwnProperty.call(item.data(), 'email')) {
          stats.emailsFound++;
          if (apply) await migrate(item, 'email');
        }
      });
      await scan('debates', async (item) => {
        stats.debatesScanned++;
        if (Object.prototype.hasOwnProperty.call(item.data(), 'aiResult')) {
          stats.aiResultsFound++;
          if (apply) await migrate(item, 'ai');
        }
      });
      if (apply) await archive.update({ status: 'completed', finishedAt: firestore.FieldValue.serverTimestamp(), ...stats });
      return { mode: apply ? 'apply' : 'dry-run', ...getStats(), ...(apply ? { archivePath: archive.path } : {}) };
    } catch (error) {
      if (apply) {
        try {
          await archive.update({ status: 'failed', finishedAt: firestore.FieldValue.serverTimestamp(), ...stats });
        } catch { /* Preserve the original failure; the archive path remains available to the operator. */ }
      }
      throw error;
    }
  };
  return { archivePath: archive.path, getStats, run };
}
