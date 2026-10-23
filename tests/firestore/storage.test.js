import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDocs, collection, Timestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, getDownloadURL, updateMetadata } from 'firebase/storage';

const projectId = 'demo-verdict-rules';
let environment;
let callables;
const functionsRequire = createRequire(new URL('../../functions/package.json', import.meta.url));

function localAddress(name) {
  const value = process.env[name];
  if (!value || !/^(127\.0\.0\.1|localhost):\d+$/.test(value)) {
    throw new Error(`${name} must point to a loopback emulator. Run npm run test:storage.`);
  }
  const [host, port] = value.split(':');
  return { host, port: Number(port) };
}

before(async () => {
  localAddress('FIREBASE_STORAGE_EMULATOR_HOST');
  localAddress('FIRESTORE_EMULATOR_HOST');
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId, storageBucket: projectId });
  callables = functionsRequire('./lib/index.js');
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      ...localAddress('FIRESTORE_EMULATOR_HOST'),
      rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
    storage: {
      ...localAddress('FIREBASE_STORAGE_EMULATOR_HOST'),
      rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await environment?.cleanup();
  await functionsRequire('firebase-admin/app').deleteApp(functionsRequire('firebase-admin/app').getApp());
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.clearStorage();
  await environment.withSecurityRulesDisabled(async (context) => {
    for (const visibilityMode of ['public', 'private', 'request_only']) {
      await setDoc(doc(context.firestore(), 'debates', visibilityMode), {
        fighter1: 'creator', fighter2: 'opponent', creatorId: 'creator',
        invitedUserId: 'invited', invitedUserIds: ['group-invited'],
        visibilityMode, accessApprovedUserIds: ['approved'],
        creationMode: visibilityMode === 'private' ? 'direct_invite' : 'public_feed',
        status: 'active', activeSpeakerId: 'creator', isRoundActive: true,
        roundIndex: 1, totalRounds: 3,
        roundEndsAt: Timestamp.fromMillis(Date.now() + 120000),
      });
      await uploadBytes(ref(context.storage(), `debates/${visibilityMode}/media/test.png`),
        new Uint8Array([1, 2, 3]), { contentType: 'image/png' });
    }
  });
});

function media(uid, visibility) {
  const context = uid ? environment.authenticatedContext(uid) : environment.unauthenticatedContext();
  return ref(context.storage(), `debates/${visibility}/media/test.png`);
}

for (const uid of ['creator', 'opponent', 'invited', 'group-invited']) {
  test(`private media: ${uid} can download`, async () => {
    const bytes = await assertSucceeds(getBytes(media(uid, 'private')));
    assert.equal(bytes.byteLength, 3);
  });
}

test('private media: outsider cannot download or obtain a download link', async () => {
  await assertFails(getBytes(media('outsider', 'private')));
  await assertFails(getDownloadURL(media('outsider', 'private')));
});

test('private media: approval for request-only does not grant private access', async () => {
  await assertFails(getBytes(media('approved', 'private')));
});

test('request-only media: approved viewer can download', async () => {
  await assertSucceeds(getBytes(media('approved', 'request_only')));
});

test('request-only media: outsider cannot download', async () => {
  await assertFails(getBytes(media('outsider', 'request_only')));
});

test('request-only media: approval revocation blocks SDK download', async () => {
  await assertSucceeds(getBytes(media('approved', 'request_only')));
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'debates', 'request_only'), { accessApprovedUserIds: [] });
  });
  await assertFails(getBytes(media('approved', 'request_only')));
});

test('public media: signed-in viewer can download', async () => {
  await assertSucceeds(getBytes(media('outsider', 'public')));
});

for (const visibility of ['public', 'private', 'request_only']) {
  test(`${visibility} media: anonymous SDK download is denied`, async () => {
    await assertFails(getBytes(media(null, visibility)));
  });
}

test('orphaned media: missing debate denies download', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), 'debates/missing/media/test.png'), new Uint8Array([1]));
  });
  await assertFails(getBytes(media('outsider', 'missing')));
});

test('upload: participant can still upload an image', async () => {
  await assertSucceeds(uploadBytes(ref(media('creator', 'private').parent, 'new-image.png'),
    new Uint8Array([4, 5, 6]), { contentType: 'image/png' }));
});

test('upload: participant can still upload audio', async () => {
  await assertSucceeds(uploadBytes(ref(media('opponent', 'private').parent, 'new-voice.m4a'),
    new Uint8Array([4, 5, 6]), { contentType: 'audio/m4a' }));
});

for (const uid of ['outsider', 'approved']) {
  test(`upload: ${uid} cannot upload to a request-only debate`, async () => {
    await assertFails(uploadBytes(media(uid, 'request_only'),
      new Uint8Array([4, 5, 6]), { contentType: 'image/png' }));
  });
}

test('upload: participant cannot upload an unsupported file type', async () => {
  await assertFails(uploadBytes(ref(media('creator', 'private').parent, 'new-file.bin'),
    new Uint8Array([4, 5, 6]), { contentType: 'application/octet-stream' }));
});

test('published media: participant cannot overwrite existing bytes', async () => {
  await assertFails(uploadBytes(media('creator', 'private'),
    new Uint8Array([9]), { contentType: 'image/png' }));
});

test('published media: participant cannot restore a bearer token', async () => {
  await assertFails(updateMetadata(media('creator', 'private'), {
    customMetadata: { firebaseStorageDownloadTokens: 'attacker-token' },
  }));
});

test('new media: real send handler finalizes to Admin-only storage and proxy enforces access', async () => {
  const path = 'debates/private/media/123_creator.png';
  const staging = ref(environment.authenticatedContext('creator').storage(), path);
  await uploadBytes(staging, new Uint8Array([7, 8, 9]), { contentType: 'image/png' });
  const oldUrl = await getDownloadURL(staging);
  await callables.sendDebateMessage.run({
    auth: { uid: 'creator', token: {} },
    data: { debateId: 'private', messageType: 'image', mediaPath: path },
  });
  let saved;
  let messageId;
  await environment.withSecurityRulesDisabled(async (context) => {
    const messages = await getDocs(collection(context.firestore(), 'debates', 'private', 'messages'));
    assert.equal(messages.size, 1);
    saved = messages.docs[0].data();
    messageId = messages.docs[0].id;
  });
  assert.ok(saved.mediaPath.startsWith('debates/private/secured/'));
  assert.equal(saved.mediaUrl, undefined);
  const secure = ref(environment.authenticatedContext('creator').storage(), saved.mediaPath);
  await assertFails(getBytes(secure));
  await assertFails(getDownloadURL(secure));
  const protectedUrl = new URL(oldUrl);
  protectedUrl.pathname = `/v0/b/${projectId}/o/${encodeURIComponent(saved.mediaPath)}`;
  const protectedResponse = await fetch(protectedUrl);
  assert.ok([401, 403, 404].includes(protectedResponse.status));
  const response = await fetch(oldUrl);
  assert.ok([401, 403, 404].includes(response.status), `staging link status: ${response.status}`);
  const request = { data: { debateId: 'private', mediaPath: saved.mediaPath } };
  const result = await callables.getDebateMedia.run({ ...request, auth: { uid: 'creator', token: {} } });
  assert.deepEqual([...Buffer.from(result.base64, 'base64')], [7, 8, 9]);
  await assert.rejects(callables.getDebateMedia.run({ ...request, auth: { uid: 'outsider', token: {} } }),
    (error) => error.code === 'permission-denied');
  await assert.rejects(callables.getDebateMedia.run(request),
    (error) => error.code === 'unauthenticated');
  await callables.deleteDebateMessages.run({ auth: { uid: 'creator', token: {} },
    data: { debateId: 'private', messageIds: [messageId] } });
  await assert.rejects(callables.getDebateMedia.run({ ...request, auth: { uid: 'creator', token: {} } }));
});

const uploadRequest = (uid = 'creator', data = {}) => ({
  ...(uid ? { auth: { uid, token: {} } } : {}),
  data: { debateId: 'private', base64: Buffer.from([7, 8, 9]).toString('base64'), contentType: 'image/png', ...data },
});
const storageBucket = () => functionsRequire('firebase-admin/storage').getStorage().bucket();
async function storedPaths() {
  const [files] = await storageBucket().getFiles();
  return files.map((file) => file.name).sort();
}
async function assertUploadRejectedWithoutStorageWrite(request, expectedCode, expectedReason) {
  const beforePaths = await storedPaths();
  await assert.rejects(callables.uploadDebateMedia.run(request), (error) => {
    assert.equal(error.code, expectedCode);
    if (expectedReason) assert.equal(error.details?.reason, expectedReason);
    return true;
  });
  assert.deepEqual(await storedPaths(), beforePaths, 'a rejected upload must not create an object');
}

for (const [contentType, messageType, suffix] of [
  ['image/png', 'image', '.png'], ['audio/mp4', 'voice', '.m4a'],
]) {
  test(`upload proxy: ${messageType} authorizes, publishes without a bearer token, and downloads through access checks`, async () => {
    const bytes = Buffer.from([7, 8, 9]);
    const upload = await callables.uploadDebateMedia.run(uploadRequest('creator', { contentType }));
    assert.deepEqual(Object.keys(upload), ['mediaPath']);
    assert.ok(upload.mediaPath.startsWith('debates/private/uploads/'));
    assert.ok(upload.mediaPath.endsWith(`_creator${suffix}`));
    assert.equal(upload.mediaUrl, undefined);
    const [stagingMetadata] = await storageBucket().file(upload.mediaPath).getMetadata();
    assert.equal(stagingMetadata.contentType, contentType);
    assert.equal(stagingMetadata.cacheControl, 'private, no-store');
    assert.equal(stagingMetadata.metadata?.firebaseStorageDownloadTokens, undefined);
    await assertFails(getBytes(ref(environment.authenticatedContext('creator').storage(), upload.mediaPath)));
    await assertFails(getDownloadURL(ref(environment.authenticatedContext('creator').storage(), upload.mediaPath)));
    const { host, port } = localAddress('FIREBASE_STORAGE_EMULATOR_HOST');
    const rawResponse = await fetch(`http://${host}:${port}/v0/b/${projectId}/o/${encodeURIComponent(upload.mediaPath)}?alt=media`);
    assert.ok([401, 403, 404].includes(rawResponse.status), `unauthenticated upload URL status: ${rawResponse.status}`);
    const [uploadedBytes] = await storageBucket().file(upload.mediaPath).download();
    assert.deepEqual(uploadedBytes, bytes);
    await assert.rejects(callables.getDebateMedia.run({ auth: { uid: 'creator', token: {} },
      data: { debateId: 'private', mediaPath: upload.mediaPath },
    }), (error) => error.code === 'invalid-argument');

    await callables.sendDebateMessage.run({ auth: { uid: 'creator', token: {} },
      data: { debateId: 'private', messageType, mediaPath: upload.mediaPath, mediaDuration: 3 },
    });
    let message;
    await environment.withSecurityRulesDisabled(async (context) => {
      const messages = await getDocs(collection(context.firestore(), 'debates', 'private', 'messages'));
      assert.equal(messages.size, 1);
      message = messages.docs[0].data();
    });
    assert.ok(message.mediaPath.startsWith('debates/private/secured/'));
    assert.equal(message.mediaUrl, undefined);
    assert.equal(message.messageType, messageType);
    if (messageType === 'voice') assert.equal(message.mediaDuration, 3);
    const [stagingExists] = await storageBucket().file(upload.mediaPath).exists();
    assert.equal(stagingExists, false);
    const [metadata] = await storageBucket().file(message.mediaPath).getMetadata();
    assert.equal(metadata.metadata?.firebaseStorageDownloadTokens, undefined);
    await assertFails(getBytes(ref(environment.authenticatedContext('creator').storage(), message.mediaPath)));
    await assertFails(getDownloadURL(ref(environment.authenticatedContext('creator').storage(), message.mediaPath)));
    const request = { data: { debateId: 'private', mediaPath: message.mediaPath } };
    const download = await callables.getDebateMedia.run({ ...request, auth: { uid: 'opponent', token: {} } });
    assert.deepEqual(Buffer.from(download.base64, 'base64'), bytes);
    await assert.rejects(callables.getDebateMedia.run({ ...request, auth: { uid: 'outsider', token: {} } }),
      (error) => error.code === 'permission-denied');
  });
}

test('upload proxy: authentication is required before storing bytes', async () => {
  await assertUploadRejectedWithoutStorageWrite(uploadRequest(null), 'unauthenticated');
});
test('upload proxy: private outsider and approved spectators cannot write', async () => {
  await assertUploadRejectedWithoutStorageWrite(uploadRequest('outsider'), 'permission-denied', 'MESSAGE_ACCESS_DENIED');
  await assertUploadRejectedWithoutStorageWrite(uploadRequest('approved', { debateId: 'request_only' }),
    'permission-denied', 'TURN_NOT_FIGHTER');
});
test('upload proxy: only the active fighter can upload', async () => {
  await assertUploadRejectedWithoutStorageWrite(uploadRequest('opponent'), 'failed-precondition', 'TURN_NOT_ACTIVE_SPEAKER');
});
test('upload proxy: banned fighter cannot upload despite owning the current turn', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'creator'), { name: 'Creator', isBanned: true });
  });
  await assertUploadRejectedWithoutStorageWrite(uploadRequest(), 'permission-denied', 'ACCOUNT_BANNED');
});
test('upload proxy: expired and finished debates reject media before touching storage', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'debates', 'private'), {
      roundEndsAt: Timestamp.fromMillis(Date.now() - 10000),
    });
  });
  await assertUploadRejectedWithoutStorageWrite(uploadRequest(), 'failed-precondition', 'TURN_TIME_EXPIRED');
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'debates', 'private'), { status: 'finished' });
  });
  await assertUploadRejectedWithoutStorageWrite(uploadRequest(), 'failed-precondition', 'MESSAGE_DEBATE_FINISHED');
});

for (const [label, patch] of [
  ['malformed alphabet', { base64: '%%%=' }],
  ['missing padding', { base64: 'YQ=' }],
  ['noncanonical pad bits', { base64: 'Zh==' }],
  ['data URL wrapper', { base64: 'data:image/png;base64,BwgJ' }],
  ['empty data', { base64: '' }],
  ['unsupported MIME', { contentType: 'application/octet-stream' }],
  ['active SVG MIME', { contentType: 'image/svg+xml' }],
]) {
  test(`upload proxy: rejects ${label} before creating a file`, async () => {
    await assertUploadRejectedWithoutStorageWrite(uploadRequest('creator', patch),
      'invalid-argument', 'MESSAGE_INVALID_MEDIA_FILE');
  });
}
test('upload proxy: payload over six MiB is rejected before storing bytes', async () => {
  await assertUploadRejectedWithoutStorageWrite(uploadRequest('creator', {
    base64: Buffer.alloc(6 * 1024 * 1024 + 1).toString('base64'),
  }), 'invalid-argument', 'MESSAGE_INVALID_MEDIA_FILE');
});
test('upload proxy: nested debate paths are rejected', async () => {
  await assertUploadRejectedWithoutStorageWrite(uploadRequest('creator', { debateId: 'private/messages' }), 'invalid-argument');
});

test('media proxy: approval permits legacy bytes and revocation denies the next download', async () => {
  const request = { auth: { uid: 'approved', token: {} },
    data: { debateId: 'request_only', mediaPath: 'debates/request_only/media/test.png' } };
  const result = await callables.getDebateMedia.run(request);
  assert.deepEqual([...Buffer.from(result.base64, 'base64')], [1, 2, 3]);
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'debates', 'request_only'), { accessApprovedUserIds: [] });
  });
  await assert.rejects(callables.getDebateMedia.run(request), (error) => error.code === 'permission-denied');
});

// Diagnostic, not a privacy guarantee: documents the existing bearer-link gap.
test('known limitation: private token link can be fetched without authentication', async () => {
  const url = await assertSucceeds(getDownloadURL(media('creator', 'private')));
  const parsed = new URL(url);
  assert.ok(['localhost', '127.0.0.1'].includes(parsed.hostname));
  assert.equal(parsed.port, String(localAddress('FIREBASE_STORAGE_EMULATOR_HOST').port));
  const response = await fetch(url);
  assert.equal(response.status, 200);
  assert.equal((await response.arrayBuffer()).byteLength, 3);
});
