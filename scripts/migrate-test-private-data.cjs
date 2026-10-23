#!/usr/bin/env node
// This wrapper is restricted to the isolated test database. No writes without --apply.
const { createRequire } = require('node:module');
const { execFileSync } = require('node:child_process');
const { resolve } = require('node:path');
const projectId = 'verdict-test-1471f';
const databaseId = 'default';

function validateSelection() {
  const args = process.argv.slice(2);
  if (args.length > 1 || args.some((arg) => arg !== '--apply')) {
    throw new Error('Only a single --apply is supported; default is a dry run.');
  }
  if (process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Use the separate emulator tests, not this cloud migration command.');
  for (const key of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'DEVSHELL_PROJECT_ID']) {
    if (process.env[key] && process.env[key] !== projectId) throw new Error(`Refusing another selected project in ${key}.`);
  }
  if (process.env.FIRESTORE_DATABASE_ID && process.env.FIRESTORE_DATABASE_ID !== databaseId) {
    throw new Error('Refusing another selected Firestore database.');
  }
  if (process.env.FIREBASE_CONFIG) {
    const configured = JSON.parse(process.env.FIREBASE_CONFIG).projectId;
    if (configured && configured !== projectId) throw new Error('Refusing another selected project in FIREBASE_CONFIG.');
  }
  // Cloud Shell exposes its project through gcloud as well as environment variables.
  // Reading this selection does not change it or grant any access.
  let selected;
  try {
    selected = execFileSync('gcloud', ['config', 'get-value', 'project'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 10000,
    }).trim();
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error('Cannot verify the gcloud project selection.');
  }
  if (selected && selected !== '(unset)' && selected !== projectId) throw new Error('Refusing another selected gcloud project.');
  return args.includes('--apply');
}

async function main() {
  const apply = validateSelection();
  const requireFunctions = createRequire(resolve(__dirname, '../functions/package.json'));
  const { initializeApp, deleteApp } = requireFunctions('firebase-admin/app');
  const { getFirestore } = requireFunctions('firebase-admin/firestore');
  const { createPrivateDataMigrationController } = requireFunctions('./lib/private_data_migration');
  const app = initializeApp({ projectId });
  const migration = createPrivateDataMigrationController(getFirestore(app, databaseId));
  // Print the recovery location before any attempt to archive or remove data.
  console.log(JSON.stringify({ projectId, database: databaseId, mode: apply ? 'apply' : 'dry-run',
    ...(apply ? { archivePath: migration.archivePath } : {}) }));
  try {
    console.log(JSON.stringify({ projectId, database: databaseId, ...await migration.run({ apply }) }, null, 2));
  } catch (error) {
    console.error(JSON.stringify({ status: 'failed', ...migration.getStats(),
      ...(apply ? { archivePath: migration.archivePath } : {}), error: error.message }));
    process.exitCode = 1;
  } finally { await deleteApp(app); }
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
