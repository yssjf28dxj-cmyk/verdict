const test = require('node:test');
const assert = require('node:assert/strict');

const {
  assertCanAdvanceOrFinish,
  assertCanCancelDebate,
  assertCanCastVote,
  assertCanCreateDebate,
  assertCanFinishDebate,
  assertCanSendMessage,
  evaluateAcceptGuard,
  assertTransitionInvariants,
} = require('../lib/domain/debate/guards.js');

function expectHttpsError(fn, expectedReason) {
  try {
    fn();
    assert.fail(`Expected HttpsError with reason ${expectedReason}`);
  } catch (error) {
    assert.equal(error?.details?.reason, expectedReason);
  }
}

test('accept guard allows waiting debate accept', () => {
  const result = evaluateAcceptGuard({
    uid: 'u2',
    status: 'waiting',
    fighter1: 'u1',
    fighter2: '',
    invitedUserId: '',
    opponentId: '',
    creationMode: 'public_feed',
    strictTransitionsEnabled: true,
  });

  assert.equal(result.noop, false);
});

test('accept guard returns noop for already accepted actor', () => {
  const result = evaluateAcceptGuard({
    uid: 'u2',
    status: 'active',
    fighter1: 'u1',
    fighter2: 'u2',
    invitedUserId: '',
    opponentId: 'u2',
    creationMode: 'public_feed',
    strictTransitionsEnabled: true,
  });

  assert.equal(result.noop, true);
});

test('accept guard rejects conflict when opponent already reserved', () => {
  expectHttpsError(() => {
    evaluateAcceptGuard({
      uid: 'u3',
      status: 'waiting',
      fighter1: 'u1',
      fighter2: 'u2',
      invitedUserId: '',
      opponentId: 'u2',
      creationMode: 'public_feed',
      strictTransitionsEnabled: true,
    });
  }, 'ACCEPT_OPPONENT_ALREADY_SET');
});

test('transition invariants reject immutable mutation after finish', () => {
  expectHttpsError(() => {
    assertTransitionInvariants(
      {
        status: 'finished',
        fighter1: 'u1',
        fighter2: 'u2',
        votes1: 1,
        votes2: 0,
        winner: 'fighter1',
      },
      {
        status: 'finished',
        fighter1: 'u1',
        fighter2: 'u3',
        votes1: 1,
        votes2: 0,
        winner: 'fighter1',
      },
    );
  }, 'INVARIANT_FINISHED_IMMUTABLE');
});

test('message permission matrix: active speaker fighter is allowed', () => {
  const result = assertCanSendMessage({
    uid: 'u1',
    debate: {
      creatorId: 'u1',
      fighter1: 'u1',
      fighter2: 'u2',
      activeSpeakerId: 'u1',
      isRoundActive: true,
      roundIndex: 1,
    },
    hasReadAccess: true,
    status: 'active',
    isPlayableStatus: true,
  });

  assert.equal(result.roundIndex, 1);
});

test('message permission matrix: viewer cannot message', () => {
  expectHttpsError(() => {
    assertCanSendMessage({
      uid: 'viewer',
      debate: {
        creatorId: 'u1',
        fighter1: 'u1',
        fighter2: 'u2',
        activeSpeakerId: 'u1',
        isRoundActive: true,
      },
      hasReadAccess: true,
      status: 'active',
      isPlayableStatus: true,
    });
  }, 'TURN_NOT_FIGHTER');
});

test('vote permission matrix: viewer can vote, fighters cannot', () => {
  const ok = assertCanCastVote({
    uid: 'viewer',
    debate: {
      creatorId: 'u1',
      fighter1: 'u1',
      fighter2: 'u2',
      roundIndex: 2,
    },
    hasReadAccess: true,
    status: 'active',
    isPlayableStatus: true,
  });
  assert.equal(ok.roundIndex, 2);

  expectHttpsError(() => {
    assertCanCastVote({
      uid: 'u1',
      debate: {
        creatorId: 'u1',
        fighter1: 'u1',
        fighter2: 'u2',
      },
      hasReadAccess: true,
      status: 'active',
      isPlayableStatus: true,
    });
  }, 'VOTE_FIGHTER_FORBIDDEN');
});

test('finish permission matrix: only participants can finish', () => {
  assert.doesNotThrow(() => {
    assertCanAdvanceOrFinish({
      uid: 'u1',
      debate: {
        creatorId: 'u1',
        fighter1: 'u1',
        fighter2: 'u2',
      },
    });
  });

  expectHttpsError(() => {
    assertCanAdvanceOrFinish({
      uid: 'viewer',
      debate: {
        creatorId: 'u1',
        fighter1: 'u1',
        fighter2: 'u2',
      },
    });
  }, 'ADVANCE_NOT_PARTICIPANT');
});

test('finish guard rejects non-active status', () => {
  expectHttpsError(() => {
    assertCanFinishDebate({
      debate: {
        creatorId: 'u1',
        fighter1: 'u1',
        fighter2: 'u2',
      },
      status: 'waiting',
    });
  }, 'FINISH_STATUS_INVALID');
});

test('create guard accepts valid payload', () => {
  assert.doesNotThrow(() => {
    assertCanCreateDebate({
      uid: 'u1',
      topic: 'Valid topic',
      durationSeconds: 180,
      totalRounds: 3,
      creationMode: 'public_feed',
      visibilityMode: 'public',
      languageCode: 'ru',
      region: 'global',
      invitedUserId: '',
      allowedCreationModes: ['public_feed', 'direct_invite'],
      allowedVisibilityModes: ['public', 'request_only', 'private'],
      allowedLanguages: ['ru', 'en', 'ar'],
      allowedRegions: ['global', 'cis', 'mena', 'europe_africa'],
      allowedDurations: [30, 60, 90, 120, 180, 300, 420, 600],
      allowedRounds: [1, 3, 5],
    });
  });
});

test('cancel guard allows only creator in waiting status', () => {
  assert.doesNotThrow(() => {
    assertCanCancelDebate({
      uid: 'creator',
      creatorId: 'creator',
      status: 'waiting',
    });
  });

  expectHttpsError(() => {
    assertCanCancelDebate({
      uid: 'viewer',
      creatorId: 'creator',
      status: 'waiting',
    });
  }, 'CANCEL_NOT_CREATOR');
});

const open = { fighter1: 'u1', fighter2: 'u2', activeSpeakerId: 'u1', roundIndex: 1,
  totalRounds: 3, schemaVersion: 2, isRoundActive: true,
  roundEndsAt: { toMillis: () => Date.now() + 60000 } };
const sendParams = (patch) => ({ uid: 'u1', debate: { ...open, ...patch },
  hasReadAccess: true, status: 'active', isPlayableStatus: true });
const voteParams = (patch) => ({ uid: 'viewer', debate: { ...open, ...patch },
  hasReadAccess: true, status: 'active', isPlayableStatus: true });

test('canonical message rejects a missing speaker instead of admitting both fighters', () => {
  expectHttpsError(() => assertCanSendMessage(sendParams({ activeSpeakerId: '' })), 'TURN_NOT_ASSIGNED');
});
test('canonical message rejects missing and malformed deadlines', () => {
  for (const roundEndsAt of [undefined, null, {}, { toMillis: () => NaN }]) {
    expectHttpsError(() => assertCanSendMessage(sendParams({ roundEndsAt })), 'TURN_DEADLINE_INVALID');
  }
});
test('expired message is blocked exactly at the inclusive deadline', () => {
  expectHttpsError(() => assertCanSendMessage(sendParams({ roundEndsAt: { toMillis: () => Date.now() } })), 'TURN_TIME_EXPIRED');
});
test('voting fails closed for expired or malformed timers while task delivery lags', () => {
  expectHttpsError(() => assertCanCastVote(voteParams({ roundEndsAt: { toMillis: () => Date.now() - 1 } })), 'VOTE_TIME_EXPIRED');
  expectHttpsError(() => assertCanCastVote(voteParams({ roundEndsAt: {} })), 'VOTE_DEADLINE_INVALID');
});
test('inactive round rejects voting before a final status update', () => {
  expectHttpsError(() => assertCanCastVote(voteParams({ isRoundActive: false })), 'ROUND_NOT_ACTIVE');
});
test('transition rejects fractional and non-finite round indexes', () => {
  for (const roundIndex of [NaN, 1.5, Infinity]) {
    expectHttpsError(() => assertTransitionInvariants({}, { ...open, status: 'active', roundIndex }), 'INVARIANT_ROUND_RANGE_INVALID');
  }
});
