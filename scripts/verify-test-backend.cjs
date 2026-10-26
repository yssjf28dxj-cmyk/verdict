#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const PROJECT = 'verdict-test-1471f';
const REGION = 'us-central1';
function expectedFunctions(root) {
  const names = new Set();
  for (const script of ['deploy-test-foundation.sh', 'deploy-test-deadlines.sh']) {
    const source = fs.readFileSync(path.join(root, 'scripts', script), 'utf8');
    for (const match of source.matchAll(/functions:([A-Za-z]\w*)(?![\w:])/g)) names.add(match[1]);
  }
  if (!names.size) throw new Error('No expected functions found.');
  return [...names].sort();
}
function assessBackend(functions, expected) {
  const failures = [];
  if (!Array.isArray(functions)) throw new Error('Expected a Functions list.');
  if (!Array.isArray(expected) || !expected.length) throw new Error('Expected a nonempty release manifest.');
  for (const name of expected) {
    const fullName = `projects/${PROJECT}/locations/${REGION}/functions/${name}`;
    const matches = functions.filter(fn => fn?.name === fullName);
    if (matches.length !== 1) { failures.push(`${name}: missing or duplicate function in the expected test region.`); continue; }
    const fn = matches[0];
    if (fn.state !== 'ACTIVE') failures.push(`${name}: state ${fn.state ?? 'unknown'}, expected ACTIVE.`);
    if (fn.environment !== 'GEN_2') failures.push(`${name}: expected GEN_2.`);
    if (fn.buildConfig?.runtime !== 'nodejs22') failures.push(`${name}: expected nodejs22.`);
  }
  return { ok: failures.length === 0, project: PROJECT, region: REGION,
    expectedCount: expected.length, failures,
    unchecked: ['Deployed source commit', 'IAM and Cloud Tasks delivery', 'Deployed rules and indexes',
      'APK 4004 device compatibility', 'FCM delivery and iOS acceptance'] };
}
module.exports = { expectedFunctions, assessBackend };
if (require.main === module) {
  try {
    const expected = expectedFunctions(path.resolve(__dirname, '..'));
    const output = execFileSync('gcloud', ['functions', 'list', '--v2', `--project=${PROJECT}`, '--format=json'],
      { encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
    const report = assessBackend(JSON.parse(output), expected);
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    process.exitCode = report.ok ? 0 : 1;
  } catch {
    process.stderr.write('Cannot verify test backend. Check gcloud authentication, permissions and connectivity. Deployment is not confirmed.\n');
    process.exitCode = 1;
  }
}
