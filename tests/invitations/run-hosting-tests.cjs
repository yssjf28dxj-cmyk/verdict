const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const source = JSON.parse(fs.readFileSync(path.join(root, 'firebase.invites.staging.json'), 'utf8'));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'verdict-invitation-tests-'));
const quote = (value) => `'${value.replaceAll("'", "'\\''")}'`;
try {
  const config = path.join(temporary, 'firebase.json');
  fs.cpSync(path.resolve(root, source.hosting.public), path.join(temporary, 'public'), { recursive: true });
  fs.writeFileSync(config, JSON.stringify({
    hosting: { ...source.hosting, public: 'public' },
    emulators: { hosting: { host: '127.0.0.1', port: 5005 }, ui: { enabled: false }, singleProjectMode: true },
  }));
  const result = spawnSync(path.join(root, 'tests/firestore/node_modules/.bin/firebase'), [
    'emulators:exec', '--config', config, '--project', 'demo-verdict-invitations', '--only', 'hosting',
    `${quote(process.execPath)} --test ${quote(path.join(__dirname, 'served.mjs'))}`,
  ], { cwd: root, stdio: 'inherit', env: { ...process.env, VERDICT_INVITATION_EMULATOR_HOST: '127.0.0.1:5005' } });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
