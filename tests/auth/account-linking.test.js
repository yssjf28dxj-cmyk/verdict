import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

const project = 'demo-verdict-accounts';
const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host || '')) {
  throw new Error('Only the loopback Firebase Auth emulator may be used.');
}
const base = `http://${host}`;
async function api(action, body) {
  const response = await fetch(`${base}/identitytoolkit.googleapis.com/v1/accounts:${action}?key=emulator-only`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  return { status: response.status, ...(await response.json()) };
}
async function guest() {
  const result = await api('signUp', { returnSecureToken: true });
  assert.equal(result.status, 200);
  return result;
}
const link = (session, email = 'fighter@example.test') => api('update', {
  idToken: session.idToken, email, password: 'original-password-0123', returnSecureToken: true,
});
async function lookup(token) {
  const result = await api('lookup', { idToken: token });
  assert.equal(result.status, 200);
  return result.users[0];
}
beforeEach(async () => {
  const response = await fetch(`${base}/emulator/v1/projects/${project}/accounts`, { method: 'DELETE' });
  assert.equal(response.status, 200);
});

test('email linking and later sign-in retain the guest UID', async () => {
  const original = await guest();
  const saved = await link(original);
  assert.equal(saved.status, 200);
  assert.equal(saved.localId, original.localId);
  const restored = await api('signInWithPassword', {
    email: 'fighter@example.test', password: 'original-password-0123', returnSecureToken: true,
  });
  assert.equal(restored.status, 200);
  assert.equal(restored.localId, original.localId);
  assert.equal((await lookup(restored.idToken)).providerUserInfo[0].providerId, 'password');
});

test('an occupied email never merges or replaces a second guest', async () => {
  const owner = await guest();
  assert.equal((await link(owner)).status, 200);
  const other = await guest();
  const rejected = await link(other);
  assert.equal(rejected.status, 400);
  assert.match(rejected.error.message, /EMAIL_EXISTS/);
  const unchanged = await lookup(other.idToken);
  assert.equal(unchanged.localId, other.localId);
  assert.equal(unchanged.email, undefined);
  assert.equal(unchanged.providerUserInfo?.length ?? 0, 0);
});

test('verification confirms the linked email without changing the UID', async () => {
  const original = await guest();
  const saved = await link(original);
  const sent = await api('sendOobCode', { requestType: 'VERIFY_EMAIL', idToken: saved.idToken });
  assert.equal(sent.status, 200);
  const codes = await (await fetch(`${base}/emulator/v1/projects/${project}/oobCodes`)).json();
  const code = codes.oobCodes.find((row) => row.requestType === 'VERIFY_EMAIL' && row.email === 'fighter@example.test');
  assert.ok(code);
  const verified = await api('update', { oobCode: code.oobCode });
  assert.equal(verified.status, 200);
  const user = await lookup(saved.idToken);
  assert.equal(user.localId, original.localId);
  assert.equal(user.emailVerified, true);
});

test('password reset restores the same fighter instead of creating a new account', async () => {
  const original = await guest();
  await link(original);
  assert.equal((await api('sendOobCode', { requestType: 'PASSWORD_RESET', email: 'fighter@example.test' })).status, 200);
  const codes = await (await fetch(`${base}/emulator/v1/projects/${project}/oobCodes`)).json();
  const code = codes.oobCodes.find((row) => row.requestType === 'PASSWORD_RESET' && row.email === 'fighter@example.test');
  assert.ok(code);
  assert.equal((await api('resetPassword', { oobCode: code.oobCode, newPassword: 'new-password-4567' })).status, 200);
  const restored = await api('signInWithPassword', {
    email: 'fighter@example.test', password: 'new-password-4567', returnSecureToken: true,
  });
  assert.equal(restored.status, 200);
  assert.equal(restored.localId, original.localId);
});

test('Google linking retains the guest UID and a credential conflict leaves the other guest intact', async () => {
  const original = await guest();
  // Auth emulator accepts unsigned test-provider tokens, never real OAuth credentials.
  const token = `${Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url')}.${Buffer.from(JSON.stringify({
    iss: 'https://accounts.google.com', sub: 'emulated-google-person', email: 'google@example.test', email_verified: true,
    aud: 'emulator-only', iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600,
  })).toString('base64url')}.`;
  const request = (idToken) => ({ idToken, requestUri: 'http://localhost', returnSecureToken: true,
    postBody: new URLSearchParams({ providerId: 'google.com', id_token: token }).toString() });
  const saved = await api('signInWithIdp', request(original.idToken));
  assert.equal(saved.status, 200);
  assert.equal(saved.localId, original.localId);
  const restored = await api('signInWithIdp', request(undefined));
  assert.equal(restored.status, 200);
  assert.equal(restored.localId, original.localId);
  const other = await guest();
  const rejected = await api('signInWithIdp', request(other.idToken));
  assert.equal(rejected.status, 400);
  assert.match(rejected.error.message, /FEDERATED_USER_ID_ALREADY_LINKED/);
  assert.equal((await lookup(other.idToken)).localId, other.localId);
  assert.equal((await lookup(other.idToken)).providerUserInfo?.length ?? 0, 0);
});
