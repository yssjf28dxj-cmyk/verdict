#!/usr/bin/env bash
# Run from the reviewed codex/verdict-test-setup branch, in the owner's Cloud Shell.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
PROJECT_ID=verdict-test-1471f
REGION=us-central1
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) process.exit(1)'
gcloud firestore databases describe --database=default --project="$PROJECT_ID" --format='value(name)'
npm --prefix functions ci
npm --prefix functions run build
node --test functions/test/*.test.js
# Read the real runtime identity, without requesting private keys.
RUNTIME_SA="$(gcloud functions describe sendDebateMessage --gen2 --region="$REGION" --project="$PROJECT_ID" --format='value(serviceConfig.serviceAccountEmail)')"
[[ "$RUNTIME_SA" == *@*.gserviceaccount.com ]] || { echo 'Runtime identity not found'; exit 1; }
gcloud services enable cloudtasks.googleapis.com --project="$PROJECT_ID"
# Enqueue tasks, using only this service account as the OIDC identity.
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$RUNTIME_SA" --role=roles/cloudtasks.enqueuer --condition=None --quiet
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" --project="$PROJECT_ID" --member="serviceAccount:$RUNTIME_SA" --role=roles/iam.serviceAccountUser --condition=None --quiet
# Remove cached build images older than seven days, never Firestore/Storage data.
npx --yes firebase-tools@14.27.0 functions:artifacts:setpolicy --location="$REGION" --days=7 --force --project="$PROJECT_ID" --non-interactive
# Deploy the private task handler before enabling the Firestore scheduling trigger.
npx --yes firebase-tools@14.27.0 deploy --only functions:advanceDebateTurnTask --project="$PROJECT_ID" --config firebase.staging.json --non-interactive
TASK_SERVICE="$(gcloud functions describe advanceDebateTurnTask --gen2 --region="$REGION" --project="$PROJECT_ID" --format='value(serviceConfig.service)')"
[[ -n "$TASK_SERVICE" ]] || { echo 'Task service not found'; exit 1; }
gcloud run services add-iam-policy-binding "${TASK_SERVICE##*/}" --region="$REGION" --project="$PROJECT_ID" --member="serviceAccount:$RUNTIME_SA" --role=roles/run.invoker --condition=None --quiet
npx --yes firebase-tools@14.27.0 deploy --only functions:scheduleDebateTurnDeadline,functions:autoAdvanceLiveDebates,functions:advanceRoundOrFinish,functions:yieldTurn,functions:sendDebateMessage --project="$PROJECT_ID" --config firebase.staging.json --non-interactive
# Confirm actual identities after deployment; they can differ across generations.
for FUNCTION_NAME in advanceDebateTurnTask scheduleDebateTurnDeadline autoAdvanceLiveDebates advanceRoundOrFinish yieldTurn; do
  ACTUAL_SA="$(gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" --project="$PROJECT_ID" --format='value(serviceConfig.serviceAccountEmail)')"
  [[ "$ACTUAL_SA" == *@*.gserviceaccount.com ]] || { echo 'Runtime identity not found'; exit 1; }
  if [[ "$ACTUAL_SA" != "$RUNTIME_SA" ]]; then
    gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$ACTUAL_SA" --role=roles/cloudtasks.enqueuer --condition=None --quiet
    gcloud iam service-accounts add-iam-policy-binding "$ACTUAL_SA" --project="$PROJECT_ID" --member="serviceAccount:$ACTUAL_SA" --role=roles/iam.serviceAccountUser --condition=None --quiet
    gcloud run services add-iam-policy-binding "${TASK_SERVICE##*/}" --region="$REGION" --project="$PROJECT_ID" --member="serviceAccount:$ACTUAL_SA" --role=roles/run.invoker --condition=None --quiet
  fi
done
echo 'Deadline functions deployed. Verify with a NEW text debate and both apps closed.'
