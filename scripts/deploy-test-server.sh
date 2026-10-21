#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22 or newer is required"); process.exit(1); }'
gcloud firestore databases describe --database=default --project=verdict-test-1471f --format='value(name)'
npm --prefix functions ci
npm --prefix functions run build
node --test functions/test/*.test.js
npx --yes firebase-tools@14.27.0 deploy --only firestore:indexes,functions --project verdict-test-1471f --config firebase.staging.json --non-interactive
