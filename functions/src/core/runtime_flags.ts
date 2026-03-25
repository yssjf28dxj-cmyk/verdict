import * as admin from 'firebase-admin';

export type CoreRuntimeFlags = {
  canonicalWriteEnabled: boolean;
  legacyReadEnabled: boolean;
  legacyWriteEnabled: boolean;
  strictTransitionsEnabled: boolean;
};

const DEFAULT_FLAGS: CoreRuntimeFlags = {
  canonicalWriteEnabled: false,
  legacyReadEnabled: true,
  legacyWriteEnabled: true,
  strictTransitionsEnabled: false,
};

let cachedFlags: CoreRuntimeFlags = DEFAULT_FLAGS;
let cachedAtMs = 0;
const FLAGS_CACHE_TTL_MS = 10_000;

function asBool(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

export async function getCoreRuntimeFlags(
  db: admin.firestore.Firestore,
): Promise<CoreRuntimeFlags> {
  const now = Date.now();
  if (now - cachedAtMs < FLAGS_CACHE_TTL_MS) {
    return cachedFlags;
  }

  try {
    const snap = await db.collection('admin_runtime').doc('core_flags').get();
    const data = snap.data() ?? {};
    cachedFlags = {
      canonicalWriteEnabled: asBool(
        data['canonicalWriteEnabled'],
        DEFAULT_FLAGS.canonicalWriteEnabled,
      ),
      legacyReadEnabled: asBool(
        data['legacyReadEnabled'],
        DEFAULT_FLAGS.legacyReadEnabled,
      ),
      legacyWriteEnabled: asBool(
        data['legacyWriteEnabled'],
        DEFAULT_FLAGS.legacyWriteEnabled,
      ),
      strictTransitionsEnabled: asBool(
        data['strictTransitionsEnabled'],
        DEFAULT_FLAGS.strictTransitionsEnabled,
      ),
    };
    cachedAtMs = now;
    return cachedFlags;
  } catch (_) {
    // Soft-fail to defaults so runtime flags cannot take production down.
    return cachedFlags;
  }
}
