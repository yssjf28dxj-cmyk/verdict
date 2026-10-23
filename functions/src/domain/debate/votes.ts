// Keep the existing product rule: one vote per round plus one debate vote.
// Only those keys carry votes; numeric metadata must not affect a winner.
export function countStoredVotes(
  votes: Record<string, unknown>[],
  totalRounds: number,
): { votes1: number; votes2: number } {
  if (!Number.isInteger(totalRounds) || totalRounds < 1 || totalRounds > 5) {
    throw new Error('Invalid total rounds for vote aggregation');
  }
  const keys = ['debate', ...Array.from({ length: totalRounds }, (_, i) => `round_${i + 1}`)];
  let votes1 = 0;
  let votes2 = 0;
  for (const vote of votes) {
    for (const key of keys) {
      if (vote[key] === 1) votes1++;
      else if (vote[key] === 2) votes2++;
    }
  }
  return { votes1, votes2 };
}
