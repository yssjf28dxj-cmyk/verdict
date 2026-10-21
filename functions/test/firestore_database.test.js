const test = require('node:test');
const assert = require('node:assert/strict');
const { firestoreDatabaseId } = require('../lib/firestore_database');
test('only the isolated test project uses the named database', () => {
  assert.equal(firestoreDatabaseId('verdict-test-1471f'), 'default');
  for (const project of ['verdict-final', 'demo-verdict-rules', 'other-project', undefined]) {
    assert.equal(firestoreDatabaseId(project), '(default)');
  }
});
