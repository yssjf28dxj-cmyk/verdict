# Reliable text sends

A logical text send carries a stable request ID, original sender UID and round. The server records its receipt in the message transaction. An exact retry returns the original message ID without another message; a changed payload or round with the same ID is rejected. Current access is checked on retry. New requests must satisfy the active turn and deadline. Request identities are isolated by user and debate.

The client persists the pending request before calling the server. An uncertain response preserves that identity. Restoration produces a draft, not an automatic send. Draft revision tracking prevents a late acknowledgement or restore from erasing newer edits. Local operations are serialized per UID/debate within the UI isolate.

## Compatibility and limits

- APK4004 continues through the legacy path and does not gain duplicate protection.
- Future rollout requires the compatible backend before the new client. An old backend ignores the new fields; rolling back to it removes the guarantee.
- Receipts remain with the debate without TTL. Removing receipts while retaining messages allows retries to duplicate messages. Debate deletion removes its subtree.
- SharedPreferences is app-local storage, not encrypted storage or protection against uninstall/data clearing. One pending intent is retained per user/room; intentionally changing text creates a new intent. A different user cannot reuse it; logout does not automatically send or delete it.
- Tests exercise real callable handlers against local Firestore and the Flutter callable SDK through its platform channel. They do not validate native transport, real Auth sessions, device crash persistence, or deployed Cloud Tasks.

## Combined local validation

Validated against base `887de49279e1ddfdc7132ba884da3a199c844c98` with Node 22, Java 21 and Flutter 3.41.4. The full command set is defined in `.github/workflows/verify.yml`:

- Functions build and unit tests: 67 passed.
- All Firestore suites: 244 passed; Storage: 50 passed.
- Invitation checks: 4 passed; local Hosting: 3 passed; local Auth: 5 passed.
- Flutter analyze: no issues; staging: 100 passed; production: 99 passed and one expected staging-only skip.

Install pinned dependencies with `npm ci --prefix functions`, `npm ci --prefix tests/firestore` and `flutter pub get --enforce-lockfile`, then use the workflow commands. Firestore discovery includes every `*.test.js` except Storage, which runs separately. `npm test` in tests/firestore alone runs only rules tests.

The text-specific regression suite covers lost responses, concurrent retries, authorization, payload mismatch, expired/finished rounds, original sender identity and deliberately repeated equal messages. Flutter tests cover persistent requests, SDK request fields, cache races and draft revision races. Physical Android/iOS and live Firebase remain unverified. No deployment or migration is part of this change.
