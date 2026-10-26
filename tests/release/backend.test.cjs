'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { expectedFunctions, assessBackend } = require('../../scripts/verify-test-backend.cjs');
const expected = expectedFunctions(path.resolve(__dirname, '../..'));
const fixture = () => expected.map(name => ({
  name: `projects/verdict-test-1471f/locations/us-central1/functions/${name}`,
  state: 'ACTIVE', environment: 'GEN_2', buildConfig: { runtime: 'nodejs22' },
}));
test('checks every coordinated function including tasks, media and push delivery', () => {
  for (const name of ['advanceDebateTurnTask', 'scheduleDebateTurnDeadline', 'sendLiveMedia', 'deliverDebateNotification']) assert.ok(expected.includes(name));
  const report = assessBackend(fixture(), expected);
  assert.equal(report.ok, true);
  assert.ok(report.unchecked.includes('Deployed source commit'));
});
test('missing function or empty cloud list cannot pass', () => {
  for (const functions of [[], fixture().slice(1)]) assert.equal(assessBackend(functions, expected).ok, false);
});
test('active function in production or another region cannot stand in for test function', () => {
  for (const [before, after] of [['verdict-test-1471f', 'verdict-final'], ['us-central1', 'europe-west1']]) {
    const functions = fixture(); functions[0].name = functions[0].name.replace(before, after);
    assert.equal(assessBackend(functions, expected).ok, false);
  }
});
test('failed, deploying and unspecified states block confirmation', () => {
  for (const state of ['FAILED', 'DEPLOYING', undefined]) {
    const functions = fixture(); functions[0].state = state;
    assert.equal(assessBackend(functions, expected).ok, false);
  }
});
test('wrong runtime, generation or duplicate records block confirmation', () => {
  for (const change of [fn => { fn.buildConfig.runtime = 'nodejs20'; }, fn => { fn.environment = 'GEN_1'; }]) {
    const functions = fixture(); change(functions[0]); assert.equal(assessBackend(functions, expected).ok, false);
  }
  const functions = fixture(); functions.push(functions[0]);
  assert.equal(assessBackend(functions, expected).ok, false);
});
test('malformed cloud response and empty expectations fail closed', () => {
  assert.throws(() => assessBackend({}, expected));
  assert.throws(() => assessBackend([], []));
});
