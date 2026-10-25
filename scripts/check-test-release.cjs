#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const PROJECT = 'verdict-test-1471f';
const PACKAGE = 'com.example.verdict.test';
const CERTIFICATE = 'A0:F0:81:3A:62:1F:DF:1F:65:E2:78:0F:3E:F8:AC:E1:42:1F:84:9B:3A:A2:E0:CE:61:57:1C:02:B2:C4:53:78';
function checkTestRelease(root) {
  const failures = [];
  const text = name => fs.readFileSync(path.join(root, name), 'utf8');
  const json = name => JSON.parse(text(name));
  const expect = (condition, message) => { if (!condition) failures.push(message); };
  const exists = name => typeof name === 'string' && !path.isAbsolute(name)
    && !name.split(/[\\/]/).includes('..') && fs.existsSync(path.join(root, name));
  try {
    const android = json('android/app/src/staging/google-services.json');
    expect(android.project_info?.project_id === PROJECT, 'Android staging must use VERDICT Test.');
    expect(android.project_info?.storage_bucket === `${PROJECT}.firebasestorage.app`, 'Test Storage bucket mismatch.');
    expect(android.client?.some(client => client.client_info?.android_client_info?.package_name === PACKAGE), 'Test Android package missing.');
    for (const filename of ['firebase.staging.json', 'firebase.foundation.staging.json']) {
      const config = json(filename);
      expect(config.firestore?.database === 'default', `${filename}: expected named database default without parentheses.`);
      expect(exists(config.firestore?.indexes), `${filename}: indexes file missing or outside repository.`);
      expect(Array.isArray(config.functions) && config.functions.length === 1
        && config.functions[0].source === 'functions' && config.functions[0].runtime === 'nodejs22', `${filename}: expected Functions source and Node 22.`);
      expect(!config.hosting, `${filename}: backend deployment must not publish Hosting.`);
    }
    const foundation = json('firebase.foundation.staging.json');
    expect(foundation.firestore?.rules === 'firestore.rules' && exists(foundation.firestore.rules), 'Expected current Firestore rules.');
    expect(foundation.storage?.rules === 'storage.rules' && exists(foundation.storage.rules), 'Expected current Storage rules.');
    const hosting = json('firebase.invites.staging.json');
    expect(hosting.hosting?.site === PROJECT && hosting.hosting?.public === 'web/invitations', 'Invitation Hosting must use the isolated test site.');
    const association = json('web/invitations/.well-known/assetlinks.json');
    expect(association.some(entry => entry.target?.package_name === PACKAGE
      && entry.target.sha256_cert_fingerprints?.includes(CERTIFICATE)), 'App Links must retain the APK 4004 public certificate fingerprint.');
    const source = text('functions/src/index.ts');
    const exported = new Set([...source.matchAll(/export\s+const\s+(\w+)\s*=/g)].map(match => match[1]));
    const selectors = new Set();
    for (const filename of ['scripts/deploy-test-foundation.sh', 'scripts/deploy-test-deadlines.sh']) {
      const script = text(filename);
      expect(script.includes(`PROJECT_ID=${PROJECT}\n`), `${filename}: expected a fixed test project.`);
      for (const match of script.matchAll(/functions:([A-Za-z]\w*)(?![\w:])/g)) {
        selectors.add(match[1]);
        expect(exported.has(match[1]), `${filename}: unknown function ${match[1]}.`);
      }
    }
    for (const required of ['advanceDebateTurnTask', 'scheduleDebateTurnDeadline', 'sendLiveMedia',
      'requestRematch', 'setMessageReaction', 'configurePushNotifications', 'registerPushDevice',
      'unregisterPushDevice', 'queueDebateNotifications', 'deliverDebateNotification']) {
      expect(selectors.has(required), `Coordinated deployment omits ${required}.`);
    }
  } catch (error) { failures.push(`Cannot inspect release files: ${error.message}`); }
  return { ok: failures.length === 0, project: PROJECT, database: 'default', package: PACKAGE, failures,
    unchecked: ['Cloud resources and IAM', 'Actual APK certificate and version', 'Physical-device and iOS acceptance'] };
}
module.exports = { checkTestRelease };
if (require.main === module) {
  const result = checkTestRelease(path.resolve(__dirname, '..'));
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exitCode = result.ok ? 0 : 1;
}
