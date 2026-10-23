import { randomInt } from 'node:crypto';
import * as firestore from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

export type ProfileIdentityResult =
  | { status: 'ready'; publicId: string }
  | { status: 'profile_missing' }
  | { status: 'legacy_conflict' | 'invalid_legacy_id'; publicId?: string };

type AllocationResult = ProfileIdentityResult | { status: 'collision' };

export function generatePublicProfileId(): string {
  return `VERDICT-${randomInt(10000000, 100000000)}`;
}

// Preserve existing uppercase IDs, including the former UID-prefix format.
// A public identifier must also be a safe document ID for its private claim.
export function isValidPublicProfileId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Z0-9][A-Z0-9_-]{2,63}$/.test(value);
}

export function createProfileIdentityController(
  db: firestore.Firestore,
  generate: () => string = generatePublicProfileId,
): { ensure: (uid: string) => Promise<ProfileIdentityResult> } {
  const ensure = async (uid: string): Promise<ProfileIdentityResult> => {
    if (!uid || uid.length > 128 || uid.trim() !== uid || uid.includes('/') || uid === '.' || uid === '..') {
      throw new HttpsError('invalid-argument', 'Invalid user identifier.', { reason: 'PROFILE_UID_INVALID' });
    }
    const profileRef = db.collection('users').doc(uid);

    for (let attempt = 0; attempt < 8; attempt++) {
      const candidate = generate();
      if (!/^VERDICT-[1-9]\d{7}$/.test(candidate)) throw new Error('Invalid generated public profile identifier');

      const result = await db.runTransaction<AllocationResult>(async (tx) => {
        const profile = await tx.get(profileRef);
        // An identity request must never recreate a deleted or absent account.
        if (!profile.exists) return { status: 'profile_missing' };

        const storedId = profile.get('publicId');
        const hasStoredId = storedId !== undefined && storedId !== null && storedId !== '';
        if (hasStoredId && !isValidPublicProfileId(storedId)) {
          return { status: 'invalid_legacy_id' };
        }
        const publicId = hasStoredId ? storedId as string : candidate;
        const claimRef = db.collection('public_profile_ids').doc(publicId);
        const [claim, matches] = await Promise.all([
          tx.get(claimRef),
          tx.get(db.collection('users').where('publicId', '==', publicId).limit(2)),
        ]);
        const claimedByAnother = claim.exists && claim.get('uid') !== uid;
        const usedByAnother = matches.docs.some((match) => match.id !== uid);
        if (claimedByAnother || usedByAnother) {
          // Legacy ambiguity requires an explicit migration. Never silently
          // change a previously shared identifier or take another user's claim.
          return hasStoredId ? { status: 'legacy_conflict', publicId } : { status: 'collision' };
        }

        if (!claim.exists) {
          tx.create(claimRef, { uid, createdAt: firestore.FieldValue.serverTimestamp() });
        }
        if (!hasStoredId) {
          tx.update(profileRef, {
            publicId,
            publicIdVersion: 1,
            publicIdAssignedAt: firestore.FieldValue.serverTimestamp(),
          });
        }
        return { status: 'ready', publicId };
      });

      if (result.status !== 'collision') return result;
    }
    throw new HttpsError('resource-exhausted', 'Unable to allocate a profile identifier. Retry later.', {
      reason: 'PROFILE_PUBLIC_ID_EXHAUSTED',
    });
  };
  return { ensure };
}
