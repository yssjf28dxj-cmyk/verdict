#!/usr/bin/env bash
# Prepared test Hosting only. Does not deploy functions, rules, APK or production.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
PROJECT_ID=verdict-test-1471f
SITE_ID=verdict-test-1471f
node -e 'if (Number(process.versions.node.split(".")[0]) !== 22) throw new Error("Use Node.js 22"); const c = require("./firebase.invites.staging.json"); if (c.hosting.site !== "verdict-test-1471f" || c.hosting.public !== "web/invitations") throw new Error("Only test invitation Hosting is allowed");'
INVITATION_SITES_FILE="$(mktemp)"
trap 'rm -f -- "$INVITATION_SITES_FILE"' EXIT
npx --yes firebase-tools@14.27.0 hosting:sites:list --project="$PROJECT_ID" --json > "$INVITATION_SITES_FILE"
INVITATION_SITE_EXISTS="$(node -e 'const fs=require("node:fs"); const report=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); if(report.status!=="success" || !Array.isArray(report.result?.sites)) throw new Error("Unable to verify test Hosting sites"); process.stdout.write(report.result.sites.some(s => s.name.endsWith("/sites/verdict-test-1471f")) ? "yes" : "no");' "$INVITATION_SITES_FILE")"
if [[ "$INVITATION_SITE_EXISTS" == no ]]; then
  npx --yes firebase-tools@14.27.0 hosting:sites:create "$SITE_ID" --project="$PROJECT_ID" --non-interactive
fi
npx --yes firebase-tools@14.27.0 deploy --only hosting --project="$PROJECT_ID" --config firebase.invites.staging.json --non-interactive
printf '%s\n' 'Test invitation Hosting deployed. Verify App Links and the matching APK signature on a device before enabling VERDICT_INVITES_ENABLED.'
