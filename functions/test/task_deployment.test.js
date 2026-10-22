const test = require('node:test');
const assert = require('node:assert/strict');
process.env.GCLOUD_PROJECT = 'verdict-test-1471f';
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'verdict-test-1471f' });
const functions = require('../lib/index');
test('deadline handler uses default private IAM and skips broken explicit queue policy path', () => {
  const endpoint = functions.advanceDebateTurnTask.__endpoint;
  assert(endpoint.taskQueueTrigger);
  assert.equal(endpoint.taskQueueTrigger.invoker, undefined);
  assert.equal(endpoint.httpsTrigger, undefined);
  assert.equal(endpoint.omit, false);
});
test('deadline trigger is bound to the named test database and retries failures', () => {
  const trigger = functions.scheduleDebateTurnDeadline.__endpoint.eventTrigger;
  assert.equal(trigger.eventFilters.database, 'default');
  assert.equal(trigger.retry, true);
});
