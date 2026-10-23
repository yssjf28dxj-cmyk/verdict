import { test } from 'node:test';
import assert from 'node:assert/strict';

const host = process.env.VERDICT_INVITATION_EMULATOR_HOST;
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host || '')) {
  throw new Error('Invitation HTTP tests require the loopback Hosting emulator');
}
const base = `http://${host}`;
test('the invitation path serves a static landing with privacy and frame protections', async () => {
  const response = await fetch(`${base}/invite/abc_123`);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/html/);
  assert.match(response.headers.get('content-security-policy'), /default-src 'none'/);
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(response.headers.get('x-frame-options'), 'DENY');
  const html = await response.text();
  assert.ok(html.includes('VERDICT'));
  assert.equal(html.includes('firebaseConfig'), false);
  assert.equal(html.includes('abc_123'), false, 'The response must not interpolate an untrusted locator');
});
test('Android verification fetches a real JSON association file without a redirect', async () => {
  const response = await fetch(`${base}/.well-known/assetlinks.json`, { redirect: 'manual' });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /application\/json/);
  const links = await response.json();
  assert.equal(links[0].target.package_name, 'com.example.verdict.test');
});
test('the browser can load the module and CSS under the strict content policy', async () => {
  const script = await fetch(`${base}/invite.mjs`);
  assert.equal(script.status, 200);
  assert.match(script.headers.get('content-type'), /javascript/);
  assert.ok((await script.text()).includes('export function appIntent'));
  const css = await fetch(`${base}/style.css`);
  assert.equal(css.status, 200);
  assert.match(css.headers.get('content-type'), /text\/css/);
});
