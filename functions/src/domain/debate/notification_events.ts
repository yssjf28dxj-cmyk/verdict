type Data = Record<string, unknown>;
export type DebateNotificationEvent = {
  key: string; uid: string; kind: 'accepted' | 'turn' | 'finished';
};
// Only locators and event types leave this planner. Private topics/messages
// must never be copied into an OS lock-screen notification.
export function planDebateNotifications(before: Data | undefined, after: Data | undefined): DebateNotificationEvent[] {
  if (!before || !after) return [];
  const active = (value: unknown) => value === 'active' || value === 'live';
  const fighters = [after.fighter1, after.fighter2].filter((uid): uid is string =>
    typeof uid === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(uid));
  if (new Set(fighters).size !== 2) return [];
  if (after.status === 'finished' && before.status !== 'finished' && active(before.status)) {
    return fighters.map(uid => ({ key: 'finished', uid, kind: 'finished' }));
  }
  if (!active(after.status)) return [];
  const result: DebateNotificationEvent[] = [];
  if (before.status === 'waiting') {
    const creator = after.creatorId;
    if (typeof creator === 'string' && fighters.includes(creator)) {
      result.push({ key: 'accepted', uid: creator, kind: 'accepted' });
    }
  }
  const speaker = after.activeSpeakerId;
  const changed = speaker !== before.activeSpeakerId || after.roundEndsAt !== before.roundEndsAt;
  // Timestamp equality is semantic: Firestore serializes new objects for
  // unchanged values, so object identity must not create false turn alerts.
  const millis = (value: unknown): number | null => {
    if (value && typeof (value as { toMillis?: unknown }).toMillis === 'function') {
      const number = (value as { toMillis(): number }).toMillis();
      return Number.isFinite(number) ? number : null;
    }
    return null;
  };
  const deadline = millis(after.roundEndsAt);
  if (changed && deadline !== null && (speaker !== before.activeSpeakerId || deadline !== millis(before.roundEndsAt))
    && typeof speaker === 'string' && fighters.includes(speaker) && after.isRoundActive === true) {
    result.push({ key: `turn:${speaker}:${deadline}`, uid: speaker, kind: 'turn' });
  }
  return result;
}
