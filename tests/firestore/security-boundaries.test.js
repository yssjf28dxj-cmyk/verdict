import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { before, beforeEach, after, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, deleteField, Timestamp, arrayUnion } from 'firebase/firestore';
const projectId = 'demo-verdict-rules';
let environment;
const db = (uid) => environment.authenticatedContext(uid).firestore();
const waiting = {
  creatorId: 'creator', fighter1: 'creator', fighter2: '', invitedUserId: 'opponent',
  status: 'waiting', topic: 'A legitimate debate', durationSeconds: 60, roundDurationSeconds: 60,
  roundIndex: 1, currentRound: 1, votes1: 0, votes2: 0, viewerCount: 0, totalRounds: 3,
  creationMode: 'direct_invite', visibilityMode: 'request_only', languageCode: 'ru', region: 'global',
  accessRequests: ['other-requester'], accessApprovedUserIds: ['creator'],
  createdAt: Timestamp.fromMillis(1000),
};
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || '';
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Loopback emulator required');
  const [hostname, port] = host.split(':');
  environment = await initializeTestEnvironment({ projectId, firestore: {
    host: hostname, port: Number(port), rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  } });
});
after(async () => environment?.cleanup());
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'debates', 'challenge'), waiting);
    await setDoc(doc(context.firestore(), 'users', 'creator'), {
      name: 'Original', email: 'example@example.test', createdAt: Timestamp.fromMillis(1000),
      rank: 'ROOKIE', isBanned: false, stats: { wins: 3 }, publicId: 'PUBLIC-1',
      wins: 3, losses: 1, draws: 1, rating: 100, reputation: 20, viewerScore: 30,
      totalDebates: 5, debateStyle: 'Balanced', lastDebateAt: Timestamp.fromMillis(1000),
    });
    for (const visibilityMode of ['public', 'request_only', 'private']) {
      await setDoc(doc(context.firestore(), 'debates', visibilityMode), {
        ...waiting, visibilityMode, fighter2: 'opponent',
        accessApprovedUserIds: ['creator', 'opponent', 'approved'],
      });
      await setDoc(doc(context.firestore(), 'debates', visibilityMode, 'private_state', 'judgement'), {
        aiResult: { status: 'ready', winnerKey: 'A', reasoning: 'Private transcript analysis', scoreA: 60, scoreB: 40 },
      });
      await setDoc(doc(context.firestore(), 'debates', visibilityMode, 'vote_tallies', '0'), {
        votes1: 2, votes2: 1,
      });
      await setDoc(doc(context.firestore(), 'debates', visibilityMode, 'votes', 'viewer'), {
        round_1: 1, debate: 1,
      });
    }
  });
});

for (const injection of [{}, { aiResult: { winnerId: 'creator', scoreA: 100 } },
  { profileStatsApplied: true }, { roundEndsAt: Timestamp.fromMillis(9999999999999), activeSpeakerId: 'outsider' }]) {
  test(`client cannot create lifecycle data or inject server fields: ${Object.keys(injection).join(',') || 'ordinary creation'}`, async () => {
    await assertFails(setDoc(doc(db('creator'), 'debates', 'direct-create'), { ...waiting, ...injection }));
  });
}
for (const patch of [
  { roundIndex: 999, currentRound: 999 },
  { roundEndsAt: Timestamp.fromMillis(9999999999999) },
  { activeSpeakerId: 'outsider' },
  {},
]) {
  test(`invited opponent cannot accept directly and choose timeline: ${Object.keys(patch).join(',') || 'ordinary acceptance'}`, async () => {
    await assertFails(updateDoc(doc(db('opponent'), 'debates', 'challenge'), {
      fighter2: 'opponent', status: 'active', isRoundActive: true,
      activeSpeakerId: 'creator', roundEndsAt: Timestamp.fromMillis(2000), roundIndex: 1, currentRound: 1,
      accessApprovedUserIds: ['creator', 'opponent'], ...patch,
    }));
  });
}
test('creator cannot bypass transactional cancellation with direct delete', async () => {
  await assertFails(deleteDoc(doc(db('creator'), 'debates', 'challenge')));
  await assertSucceeds(getDoc(doc(db('creator'), 'debates', 'challenge')));
});

test('own access request appends without removing another requester', async () => {
  const ref = doc(db('requester'), 'debates', 'challenge');
  await assertSucceeds(updateDoc(ref, { accessRequests: arrayUnion('requester') }));
  assert.deepEqual((await getDoc(ref)).data().accessRequests, ['other-requester', 'requester']);
});
test('access request cannot overwrite all other pending requests', async () => {
  await assertFails(updateDoc(doc(db('requester'), 'debates', 'challenge'), { accessRequests: ['requester'] }));
});
test('access request cannot impersonate another new requester', async () => {
  await assertFails(updateDoc(doc(db('requester'), 'debates', 'challenge'), {
    accessRequests: ['other-requester', 'requester', 'impersonated'],
  }));
});
test('requester cannot approve themselves', async () => {
  await assertFails(updateDoc(doc(db('requester'), 'debates', 'challenge'), {
    accessRequests: arrayUnion('requester'), accessApprovedUserIds: arrayUnion('requester'),
  }));
});

for (const [field, value] of Object.entries({
  rank: 'GRANDMASTER', isBanned: false, stats: { wins: 999 }, wins: 999, losses: 0, draws: 0,
  rating: 99999, reputation: 9999, viewerScore: 9999, totalDebates: 999,
  debateStyle: 'Master', publicId: 'SOMEONE-ELSE', createdAt: Timestamp.now(), lastDebateAt: Timestamp.now(),
})) {
  test(`profile owner cannot change or remove server field ${field}`, async () => {
    const ref = doc(db('creator'), 'users', 'creator');
    // For isBanned the seeded value is false; use true so this is an actual change.
    await assertFails(updateDoc(ref, { [field]: field === 'isBanned' ? true : value }));
    await assertFails(updateDoc(ref, { [field]: deleteField() }));
  });
}
test('profile owner may rename an existing profile that contains legacy flat stats', async () => {
  const ref = doc(db('creator'), 'users', 'creator');
  await assertSucceeds(updateDoc(ref, { name: 'Changed', displayName: 'Changed', settings: { sound: false } }));
  const data = (await getDoc(ref)).data();
  assert.equal(data.wins, 3);
  assert.equal(data.rating, 100);
});
test('profile name cannot become a huge or non-text value', async () => {
  const ref = doc(db('creator'), 'users', 'creator');
  await assertFails(updateDoc(ref, { name: 'x'.repeat(51) }));
  await assertFails(updateDoc(ref, { name: { rank: 'GRANDMASTER' } }));
});
test('profile owner may not add unknown future privilege field', async () => {
  await assertFails(updateDoc(doc(db('creator'), 'users', 'creator'), { admin: true }));
});
for (const serverField of ['rank', 'isBanned', 'rating', 'wins', 'stats', 'publicId']) {
  test(`new user cannot inject ${serverField}`, async () => {
    await assertFails(setDoc(doc(db('new-user'), 'users', 'new-user'), { name: 'Valid', [serverField]: true }));
  });
}
test('a guest can still create a minimal own profile', async () => {
  await assertSucceeds(setDoc(doc(db('new-user'), 'users', 'new-user'), {
    name: 'Test 2', displayName: 'Test 2', createdAt: Timestamp.now(),
  }));
});
test('another guest cannot edit or create a profile for the original owner', async () => {
  await assertFails(updateDoc(doc(db('new-guest'), 'users', 'creator'), { name: 'Impersonated' }));
  await assertFails(setDoc(doc(db('new-guest'), 'users', 'not-their-uid'), { name: 'Impersonated' }));
});

test('an existing requester cannot add another user or inflate duplicate requests', async () => {
  const ref = doc(db('requester'), 'debates', 'challenge');
  await assertSucceeds(updateDoc(ref, { accessRequests: arrayUnion('requester') }));
  await assertFails(updateDoc(ref, { accessRequests: arrayUnion('impersonated') }));
  await assertFails(updateDoc(ref, { accessRequests: ['other-requester', 'requester', 'requester'] }));
});

for (const child of ['private_state', 'vote_tallies']) {
  const childId = child === 'private_state' ? 'judgement' : '0';
  test(`${child}: discoverable request-only card does not reveal transcript-derived data to an unapproved viewer`, async () => {
    const viewer = db('unapproved');
    await assertSucceeds(getDoc(doc(viewer, 'debates', 'request_only')));
    await assertFails(getDoc(doc(viewer, 'debates', 'request_only', child, childId)));
    await assertFails(getDocs(collection(viewer, 'debates', 'request_only', child)));
  });
  for (const viewer of ['creator', 'opponent', 'approved']) {
    test(`${child}: ${viewer} may read an approved request-only debate's data`, async () => {
      const result = await assertSucceeds(getDoc(doc(db(viewer), 'debates', 'request_only', child, childId)));
      assert.equal(result.exists(), true);
    });
  }
  test(`${child}: private debate data stays private from outsiders and approval-list-only viewers`, async () => {
    for (const viewer of ['outsider', 'approved']) {
      await assertFails(getDoc(doc(db(viewer), 'debates', 'private', child, childId)));
    }
    await assertSucceeds(getDoc(doc(db('opponent'), 'debates', 'private', child, childId)));
  });
  test(`${child}: public debate data can be read without authentication`, async () => {
    const viewer = environment.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(viewer, 'debates', 'public', child, childId)));
  });
  test(`${child}: clients cannot forge, change or delete server data even as creator`, async () => {
    for (const viewer of ['creator', 'opponent', 'approved', 'outsider']) {
      const ref = doc(db(viewer), 'debates', 'public', child, childId);
      await assertFails(updateDoc(ref, { votes1: 999, aiResult: { winnerKey: 'A' } }));
      await assertFails(deleteDoc(ref));
      await assertFails(setDoc(doc(db(viewer), 'debates', 'public', child, 'forged'), { votes1: 999 }));
    }
  });
  test(`${child}: orphan data does not become public when the parent debate is missing`, async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'debates', 'missing', child, childId), { votes1: 1 });
    });
    await assertFails(getDoc(doc(db('creator'), 'debates', 'missing', child, childId)));
  });
}

test('individual votes remain unreadable even when aggregate tallies are visible', async () => {
  for (const viewer of ['creator', 'opponent', 'approved', 'viewer']) {
    await assertSucceeds(getDoc(doc(db(viewer), 'debates', 'public', 'vote_tallies', '0')));
    await assertFails(getDoc(doc(db(viewer), 'debates', 'public', 'votes', 'viewer')));
    await assertFails(getDocs(collection(db(viewer), 'debates', 'public', 'votes')));
  }
});
test('new public profiles cannot store email', async () => {
  await assertFails(setDoc(doc(db('new-user'), 'users', 'new-user'), {
    name: 'New user', email: 'private@example.test',
  }));
});
test('owners may remove a legacy email but may not add or replace one', async () => {
  const ref = doc(db('creator'), 'users', 'creator');
  await assertFails(updateDoc(ref, { email: 'changed@example.test' }));
  await assertFails(updateDoc(ref, { email: null }));
  await assertSucceeds(updateDoc(ref, { email: deleteField() }));
  assert.equal('email' in (await getDoc(ref)).data(), false);
  await assertFails(updateDoc(ref, { email: 'private@example.test' }));
});

const legacyLobby = {
  creatorId: 'creator', opponentId: 'opponent',
  creatorTime: null, opponentTime: null, creatorReady: false, opponentReady: false,
  started: false, debateId: null, createdAt: Timestamp.fromMillis(1000),
};
test('legacy lobby invitations are a server-only archive, including for previous participants', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'lobbies', 'old-invitation'), legacyLobby);
  });
  for (const viewer of ['creator', 'opponent', 'outsider']) {
    const ref = doc(db(viewer), 'lobbies', 'old-invitation');
    await assertFails(getDoc(ref));
    await assertFails(getDocs(collection(db(viewer), 'lobbies')));
    await assertFails(updateDoc(ref, { started: true, debateId: 'forged' }));
    await assertFails(updateDoc(ref, { opponentId: 'outsider', status: 'active' }));
    await assertFails(deleteDoc(ref));
  }
  await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'lobbies', 'old-invitation')));
});
test('clients cannot revive the unused lobby lifecycle, with either legacy or forged fields', async () => {
  await assertFails(setDoc(doc(db('creator'), 'lobbies', 'new-invitation'), legacyLobby));
  await assertFails(setDoc(doc(db('creator'), 'lobbies', 'forged-invitation'), {
    ...legacyLobby, started: true, debateId: 'another-debate', status: 'active',
    aiResult: { winnerId: 'creator' }, profileStatsApplied: true,
  }));
});
test('the supported lobby screen can still read its private debate invitation as either participant', async () => {
  for (const viewer of ['creator', 'opponent']) {
    await assertSucceeds(getDoc(doc(db(viewer), 'debates', 'private')));
  }
  await assertFails(getDoc(doc(db('outsider'), 'debates', 'private')));
});

test('banned accounts cannot bypass access callables through direct request writes', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'requester'), { name: 'Banned', isBanned: true });
  });
  await assertFails(updateDoc(doc(db('requester'), 'debates', 'challenge'), {
    accessRequests: arrayUnion('requester'),
  }));
});
test('a banned creator cannot bypass access moderation through a direct write', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'users', 'creator'), { isBanned: true });
  });
  await assertFails(updateDoc(doc(db('creator'), 'debates', 'challenge'), {
    accessRequests: [], accessApprovedUserIds: ['creator', 'other-requester'],
  }));
});

test('only the active fighter can publish ephemeral activity; outsider cannot read it', async () => {
  const { serverTimestamp } = await import('firebase/firestore');
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'debates/private'), {
      status: 'active', activeSpeakerId: 'creator', roundEndsAt: Timestamp.fromMillis(Date.now() + 60000),
    });
  });
  const activity = (uid, owner = uid) => doc(db(uid), 'debates/private/activity', owner);
  const data = () => ({ status: 'typing', updatedAt: serverTimestamp() });
  await assertSucceeds(setDoc(activity('creator'), data()));
  await assertSucceeds(getDoc(activity('opponent', 'creator')));
  await assertFails(getDoc(activity('outsider', 'creator')));
  await assertFails(setDoc(activity('opponent'), data()));
  await assertFails(setDoc(activity('outsider', 'creator'), data()));
  await assertFails(setDoc(activity('creator'), { ...data(), activeSpeakerId: 'creator' }));
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'debates/private'), { status: 'finished' });
  });
  await assertFails(setDoc(activity('creator'), data()));
  await assertSucceeds(setDoc(activity('creator'), { status: '', updatedAt: serverTimestamp() }));
});

test('text receipts cannot be read, forged or deleted by clients', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'debates/public/server_text_requests/receipt'), {messageId:'message',textHash:'hash',roundIndex:1});
  });
  for (const uid of ['creator','opponent','viewer']) {
    const receipt = doc(db(uid),'debates/public/server_text_requests/receipt');
    await assertFails(getDoc(receipt));
    await assertFails(setDoc(receipt,{messageId:'forged'}));
    await assertFails(deleteDoc(receipt));
  }
});
