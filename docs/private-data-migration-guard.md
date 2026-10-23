# Private judgement migration guard

Before archiving or deleting a legacy root AI field, the migration validates any existing protected judgement within the same transaction. Empty, malformed or unknown states stop the run with the constant diagnostic `PRIVATE_JUDGEMENT_CONFLICT`; neither data contents nor document identifiers appear in that error.

For the conflicting document, root and private data remain unchanged and no field archive record is created. Run metadata can become failed, and earlier documents may already have committed. Retrying does not bypass the conflict.

Validation uses the existing AI result schema. It accepts validated ready results, historical ready results without status, and the explicit terminal states produced by `ai_judgement.ts` and the legacy sanitizer. Optional judgedAt must be a Firestore Timestamp. Unrelated metadata is preserved. A valid existing private result is never overwritten, even if the root result differs; the exact root is archived without deciding which result is correct. Missing private judgement retains the existing sanitization/transfer behavior.

## Validation

The 31 migration tests include 9 existing scenarios and 22 new cases covering malformed fields/types, known valid states, retries, partial success, concurrent migrations and concurrent private creation before its transaction read. They verify source/private preservation, absence of unwanted field archives, and exact archival when transfer succeeds.

The guard-only run used a subset: 64 non-CLI Functions tests and 140 tests from migration/rules/security-boundaries. This was not a full CI run. The combined package subsequently passed the full workflow set: 67 Functions, 244 Firestore, 50 Storage, 4 invitation, 3 Hosting, 5 Auth, Flutter analyze, 100 staging and 99 production tests with one expected skip. See `text-send-reliability.md` and `.github/workflows/verify.yml` for reproduction.

The optional `tests/firestore/firebase.migration-local.json` configuration runs Firestore on loopback port 8087. Copy current rules using `node tests/firestore/prepare-rules.js` before use. Tests use demo project `demo-verdict-rules` and SDK database `(default)`. This does not verify the cloud wrapper's named database `default`, cloud IAM, production data or workload size.

## Before any cloud application

Safe stop does not repair malformed judgement or restore fields removed by an earlier migration. It leaves existing source data in place; this is preservation, not completed privacy remediation. Protected recovery and conflict resolution require separate review. Do not restore sensitive fields into public documents.

Dry-run remains count-only and does not certify absence of these conflicts. The selected-field archive is not a complete database/Auth/Storage backup. Backup/restore verification, exact database selection and rollout authorization remain separate requirements. Old media token URLs are unchanged. No migration, recovery or deployment has been performed by this change.
