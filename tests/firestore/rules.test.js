import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion, collection, deleteField, doc, getDoc, getDocs,
  query, setDoc, updateDoc, where, or, and, orderBy, limit, Timestamp,
} from 'firebase/firestore';

const projectId = 'demo-verdict-rules';
let environment;

before(async () => {
  // Fail closed: never fall back to a real Firebase project or remote host.
  const address = process.env.FIRESTORE_EMULATOR_HOST;
  if (!address || !/^(127\.0\.0\.1|localhost):\d+$/.test(address)) {
    throw new Error('A loopback FIRESTORE_EMULATOR_HOST is required. Run npm test.');
  }
  const [host, port] = address.split(':');
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host, port: Number(port),
      rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await environment?.cleanup();
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const visibilityMode of ['public', 'private', 'request_only']) {
      await setDoc(doc(db, 'debates', visibilityMode), {
        creatorId: 'creator', fighter1: 'creator', fighter2: 'opponent',
        invitedUserId: 'opponent', invitedUserIds: [],
        creationMode: 'direct_invite', visibilityMode,
        status: 'active', topic: 'A test debate',
        createdAt: Timestamp.fromMillis(1000),
        accessRequests: [], accessApprovedUserIds: ['creator', 'opponent', 'approved'],
      });
      await setDoc(doc(db, 'debates', visibilityMode, 'messages', 'message'), {
        text: 'Test argument', senderId: 'creator',
      });
    }
  });
});

const database = (uid) => environment.authenticatedContext(uid).firestore();
const debate = (db, id) => doc(db, 'debates', id);
const message = (db, id) => doc(db, 'debates', id, 'messages', 'message');

// Match debateCardAccessFilter in lib/utils/debate_query_access.dart.
const cardAccess = (uid) => or(
  where('visibilityMode', 'in', ['public', 'request_only']),
  where('fighter1', '==', uid),
  where('fighter2', '==', uid),
  where('creatorId', '==', uid),
  where('invitedUserId', '==', uid),
  where('invitedUserIds', 'array-contains', uid),
);
const feed = (db, uid) => query(collection(db, 'debates'), cardAccess(uid),
  orderBy('createdAt', 'desc'), limit(50));
const ids = (snapshot) => snapshot.docs.map((item) => item.id).sort();

test('client access: invitation array query is allowed', async () => {
  const db = database('viewer');
  await assertSucceeds(getDocs(query(collection(db, 'debates'),
    where('invitedUserIds', 'array-contains', 'viewer'))));
});

test('client access: public cards and scalar participant queries can be combined', async () => {
  const db = database('viewer');
  await assertSucceeds(getDocs(query(collection(db, 'debates'), or(
    where('visibilityMode', 'in', ['public', 'request_only']),
    where('fighter1', '==', 'viewer'), where('fighter2', '==', 'viewer'),
    where('creatorId', '==', 'viewer'), where('invitedUserId', '==', 'viewer'),
  ))));
});

test('client feed: outsider receives discoverable cards but no private debate', async () => {
  const snapshot = await assertSucceeds(getDocs(feed(database('outsider'), 'outsider')));
  assert.deepEqual(ids(snapshot), ['public', 'request_only']);
});

for (const role of ['fighter1', 'fighter2', 'creatorId', 'invitedUserId', 'invitedUserIds']) {
  test(`client feed: private debate remains visible through ${role}`, async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(debate(context.firestore(), 'private'), {
        [role]: role === 'invitedUserIds' ? ['viewer'] : 'viewer',
      });
    });
    const snapshot = await assertSucceeds(getDocs(feed(database('viewer'), 'viewer')));
    assert.deepEqual(ids(snapshot), ['private', 'public', 'request_only']);
  });
}

for (const fighter of ['fighter1', 'fighter2']) {
  test(`client profile: ${fighter} owner can still query their own private history`, async () => {
    const owner = fighter === 'fighter1' ? 'creator' : 'opponent';
    const db = database(owner);
    const snapshot = await assertSucceeds(getDocs(query(collection(db, 'debates'),
      and(where(fighter, '==', owner), cardAccess(owner)), limit(20))));
    assert.deepEqual(ids(snapshot), ['private', 'public', 'request_only']);
  });

  test(`client profile: ${fighter} history hides private debates from outsiders`, async () => {
    const owner = fighter === 'fighter1' ? 'creator' : 'opponent';
    const db = database('outsider');
    const snapshot = await assertSucceeds(getDocs(query(collection(db, 'debates'),
      and(where(fighter, '==', owner), cardAccess('outsider')), limit(20))));
    assert.deepEqual(ids(snapshot), ['public', 'request_only']);
  });

  test(`client profile: ${fighter} history includes a private debate shared with viewer`, async () => {
    const owner = fighter === 'fighter1' ? 'creator' : 'opponent';
    const viewer = fighter === 'fighter1' ? 'opponent' : 'creator';
    const db = database(viewer);
    const snapshot = await assertSucceeds(getDocs(query(collection(db, 'debates'),
      and(where(fighter, '==', owner), cardAccess(viewer)), limit(20))));
    assert.deepEqual(ids(snapshot), ['private', 'public', 'request_only']);
  });
}

test('client feed: newest accessible debates are returned first', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(debate(context.firestore(), 'request_only'), {
      createdAt: Timestamp.fromMillis(2000),
    });
    await updateDoc(debate(context.firestore(), 'private'), {
      createdAt: Timestamp.fromMillis(3000),
    });
  });
  const snapshot = await assertSucceeds(getDocs(feed(database('opponent'), 'opponent')));
  assert.deepEqual(snapshot.docs.map((item) => item.id), ['private', 'request_only', 'public']);
});

for (const invalidInvites of [{ outsider: true }, 'outsider']) {
  test(`private: malformed invitation ${typeof invalidInvites} does not grant access`, async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(debate(context.firestore(), 'private'), { invitedUserIds: invalidInvites });
    });
    await assertFails(getDoc(debate(database('outsider'), 'private')));
    await assertFails(getDoc(message(database('outsider'), 'private')));
  });
}

test('private: creator can read the debate and its messages', async () => {
  const db = database('creator');
  await assertSucceeds(getDoc(debate(db, 'private')));
  await assertSucceeds(getDoc(message(db, 'private')));
});

test('private: opponent can read the debate and its messages', async () => {
  const db = database('opponent');
  await assertSucceeds(getDoc(debate(db, 'private')));
  await assertSucceeds(getDoc(message(db, 'private')));
});

test('private: outsider cannot read a debate by ID or its messages', async () => {
  const db = database('outsider');
  await assertFails(getDoc(debate(db, 'private')));
  await assertFails(getDoc(message(db, 'private')));
});

test('private: outsider cannot obtain private debates through a list query', async () => {
  const db = database('outsider');
  await assertFails(getDocs(query(collection(db, 'debates'), where('visibilityMode', '==', 'private'))));
});

test('feed: unfiltered query is denied instead of leaking private debates', async () => {
  await assertFails(getDocs(collection(database('outsider'), 'debates')));
});

test('feed: authenticated viewer can list public and request-only debate cards', async () => {
  const db = database('outsider');
  await assertSucceeds(getDocs(query(collection(db, 'debates'), where('visibilityMode', 'in', ['public', 'request_only']))));
});

test('private: creator can list their own debates', async () => {
  const db = database('creator');
  await assertSucceeds(getDocs(query(collection(db, 'debates'), where('creatorId', '==', 'creator'))));
});

test('private: fighters can query their own history', async () => {
  const creator = database('creator');
  const opponent = database('opponent');
  await assertSucceeds(getDocs(query(collection(creator, 'debates'), where('fighter1', '==', 'creator'))));
  await assertSucceeds(getDocs(query(collection(opponent, 'debates'), where('fighter2', '==', 'opponent'))));
});

test('private: invited user can query invitations', async () => {
  const db = database('opponent');
  await assertSucceeds(getDocs(query(collection(db, 'debates'), where('invitedUserId', '==', 'opponent'))));
});

test('profile: outsider cannot query another fighter history without visibility constraints', async () => {
  const db = database('outsider');
  await assertFails(getDocs(query(collection(db, 'debates'), where('fighter1', '==', 'creator'))));
});

test('profile: outsider can query visible debate cards of another fighter', async () => {
  const db = database('outsider');
  await assertSucceeds(getDocs(query(collection(db, 'debates'),
    where('fighter1', '==', 'creator'), where('visibilityMode', 'in', ['public', 'request_only']))));
});

test('feed: anonymous user cannot list debates', async () => {
  const db = environment.unauthenticatedContext().firestore();
  await assertFails(getDocs(query(collection(db, 'debates'), where('visibilityMode', '==', 'public'))));
});

test('anonymous: cannot read a private debate or its messages', async () => {
  const db = environment.unauthenticatedContext().firestore();
  await assertFails(getDoc(debate(db, 'private')));
  await assertFails(getDoc(message(db, 'private')));
});

test('request_only: participant can read messages', async () => {
  await assertSucceeds(getDoc(message(database('creator'), 'request_only')));
});

test('request_only: approved viewer can read messages', async () => {
  await assertSucceeds(getDoc(message(database('approved'), 'request_only')));
});

test('request_only: viewer without approval cannot read messages', async () => {
  await assertFails(getDoc(message(database('outsider'), 'request_only')));
});

test('request_only: outsider cannot list messages', async () => {
  await assertFails(getDocs(collection(database('outsider'), 'debates', 'request_only', 'messages')));
});

test('request_only: anonymous viewer cannot read messages', async () => {
  const db = environment.unauthenticatedContext().firestore();
  await assertFails(getDoc(message(db, 'request_only')));
});

test('request_only: approved viewer can list messages', async () => {
  await assertSucceeds(getDocs(collection(database('approved'), 'debates', 'request_only', 'messages')));
});

test('request_only: revoked approval removes message access', async () => {
  const viewer = database('approved');
  await assertSucceeds(getDoc(message(viewer, 'request_only')));
  await assertSucceeds(updateDoc(debate(database('creator'), 'request_only'), {
    accessApprovedUserIds: ['creator', 'opponent'],
  }));
  await assertFails(getDoc(message(viewer, 'request_only')));
});

test('request_only: missing approval list denies outsider but allows participant', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(debate(context.firestore(), 'request_only'), {
      accessApprovedUserIds: deleteField(),
    });
  });
  await assertFails(getDoc(message(database('outsider'), 'request_only')));
  await assertSucceeds(getDoc(message(database('creator'), 'request_only')));
});

test('public: viewer can still read messages', async () => {
  await assertSucceeds(getDoc(message(database('outsider'), 'public')));
});

test('request_only: submitting a request does not grant message access', async () => {
  const db = database('outsider');
  await assertSucceeds(updateDoc(debate(db, 'request_only'), {
    accessRequests: arrayUnion('outsider'),
  }));
  await assertFails(getDoc(message(db, 'request_only')));
});

test('request_only: creator approval grants message access', async () => {
  const outsider = database('outsider');
  await assertSucceeds(updateDoc(debate(outsider, 'request_only'), {
    accessRequests: arrayUnion('outsider'),
  }));
  await assertSucceeds(updateDoc(debate(database('creator'), 'request_only'), {
    accessRequests: [], accessApprovedUserIds: arrayUnion('outsider'),
  }));
  await assertSucceeds(getDoc(message(outsider, 'request_only')));
});

test('request_only: request cannot add an unrelated AI result field', async () => {
  await assertFails(updateDoc(debate(database('outsider'), 'request_only'), {
    accessRequests: arrayUnion('outsider'), aiResult: { winnerId: 'outsider' },
  }));
});

test('request_only: request cannot delete the debate topic', async () => {
  await assertFails(updateDoc(debate(database('outsider'), 'request_only'), {
    accessRequests: arrayUnion('outsider'), topic: deleteField(),
  }));
});

test('request_only: request cannot change an existing topic', async () => {
  await assertFails(updateDoc(debate(database('outsider'), 'request_only'), {
    accessRequests: arrayUnion('outsider'), topic: 'Tampered topic',
  }));
});

test('request_only: viewer cannot approve themselves', async () => {
  await assertFails(updateDoc(debate(database('outsider'), 'request_only'), {
    accessRequests: arrayUnion('outsider'), accessApprovedUserIds: arrayUnion('outsider'),
  }));
});
