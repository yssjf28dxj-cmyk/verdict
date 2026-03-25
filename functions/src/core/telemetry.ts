import * as admin from 'firebase-admin';

export async function incrementCoreMetric(
  db: admin.firestore.Firestore,
  metric: string,
  tags: Record<string, string> = {},
): Promise<void> {
  const normalizedTags = Object.entries(tags)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}:${v}`)
    .join('|');
  const key = normalizedTags ? `${metric}|${normalizedTags}` : metric;

  try {
    await db.collection('admin_core_metrics').doc(key).set(
      {
        metric,
        tags,
        value: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (_) {
    // Telemetry should never break request flow.
  }
}

export async function logCoreEvent(
  db: admin.firestore.Firestore,
  event: string,
  payload: Record<string, unknown>,
): Promise<void> {
  try {
    await db.collection('admin_core_events').add({
      event,
      ...payload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Telemetry should never break request flow.
  }
}
