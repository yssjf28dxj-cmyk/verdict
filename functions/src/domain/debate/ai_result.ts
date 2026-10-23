export type ValidatedAiResult = {
  winnerId: string;
  winnerKey: 'fighter1' | 'fighter2' | 'draw';
  scoreA: number;
  scoreB: number;
  reasoning: string;
};

const MAX_REASONING_LENGTH = 2000;

// Model output is untrusted input. Return only the supported, validated fields.
export function validateAiResult(raw: unknown, fighter1: string, fighter2: string): ValidatedAiResult {
  if (!fighter1 || !fighter2 || fighter1 === fighter2 || fighter1 === 'draw' || fighter2 === 'draw') {
    throw new Error('Invalid debate fighters');
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error('Invalid AI result object');
  }
  const value = raw as Record<string, unknown>;
  const winnerId = value.winnerId;
  const winnerKey = winnerId === fighter1 ? 'fighter1' : winnerId === fighter2 ? 'fighter2'
    : winnerId === 'draw' ? 'draw' : null;
  if (!winnerKey || value.winnerKey !== winnerKey) {
    throw new Error('Invalid or inconsistent AI winner');
  }
  const scoreA = value.scoreA;
  const scoreB = value.scoreB;
  if (typeof scoreA !== 'number' || typeof scoreB !== 'number'
    || !Number.isFinite(scoreA) || !Number.isFinite(scoreB)
    || scoreA < 0 || scoreA > 100 || scoreB < 0 || scoreB > 100) {
    throw new Error('Invalid AI scores');
  }
  if (typeof value.reasoning !== 'string' || !value.reasoning.trim()
    || value.reasoning.length > MAX_REASONING_LENGTH) {
    throw new Error('Invalid AI reasoning');
  }
  return { winnerId: winnerId as string, winnerKey, scoreA, scoreB, reasoning: value.reasoning.trim() };
}
