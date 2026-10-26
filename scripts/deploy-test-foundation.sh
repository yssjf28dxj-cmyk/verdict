#!/usr/bin/env bash
# Coordinated test-only backend/rules rollout; install the matching new APK next.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
PROJECT_ID=verdict-test-1471f
node scripts/check-test-release.cjs
REGION=us-central1
node -e 'if (Number(process.versions.node.split(".")[0]) !== 22) { console.error("Use Node.js 22"); process.exit(1); }'
gcloud firestore databases describe --database=default --project="$PROJECT_ID" --format='value(name)'
# Real Storage provisioning cannot be checked by local emulators. Refuse to
# announce working voice upload unless the expected test bucket exists.
gcloud storage buckets describe gs://verdict-test-1471f.firebasestorage.app --project="$PROJECT_ID" --format='value(name)'
gcloud services enable fcm.googleapis.com --project="$PROJECT_ID"
npm --prefix functions ci
npm --prefix functions test
# The existing deadline script owns only test queue identities and its private handler.
bash scripts/deploy-test-deadlines.sh
# Explicit list: --force accepts idempotent trigger retry policies and never
# authorizes deleting unrelated functions. No Hosting or production config.
FUNCTIONS='functions:configurePushNotifications,functions:registerPushDevice,functions:unregisterPushDevice,functions:queueDebateNotifications,functions:deliverDebateNotification,functions:setMessageReaction,functions:requestRematch,functions:sendLiveMedia,functions:heartbeatDebateViewer,functions:createDebate,functions:acceptDebateInvite,functions:requestDebateAccess,functions:moderateAccessRequest,functions:cancelDebateChallenge,functions:sendDebateMessage,functions:getDebateMedia,functions:deleteDebateMessages,functions:uploadDebateMedia,functions:finalizeBattle,functions:yieldTurn,functions:sendWorldMessage,functions:applyPenalty,functions:castVote,functions:getMyVoteStatus,functions:advanceRoundOrFinish,functions:initDebateOnCreate,functions:autoAdvanceLiveDebates,functions:applyDebateResultToProfiles,functions:ensureProfileIdentity,functions:initializeProfileIdentity,functions:getAdministrativeAccess,functions:adminDeleteDebate,functions:adminBanUser,functions:adminClearWorldChat,functions:migrateLegacyNamePlaceholders'
npx --yes firebase-tools@14.27.0 deploy --only "$FUNCTIONS,firestore:rules,firestore:indexes,storage" --project="$PROJECT_ID" --config firebase.foundation.staging.json --non-interactive --force
node scripts/verify-test-backend.cjs
node scripts/migrate-test-private-data.cjs
printf '%s\n' 'Test deployment commands completed and expected Functions are ACTIVE. Legacy privacy report is above; no migration applied.' 'FIRST verify installed APK 4004: login, text, voice, handoff and finish. Only then accept a separately prepared update APK.'
