# Text room recovery

Base 00d23ee0af8fd5802862e1282c7ccb87ee502042. Local-only scope.

Invariants: server deadlines continue without clients; returning never resets a deadline; expired/cached/unconfirmed turns cannot enable text input; an older round or active snapshot cannot revive an observed finished debate; leaving/disposal cannot install new listeners after asynchronous initialization. Disconnect/route exit is not surrender and must not erase debate or results. Pending request identity remains owned by the existing persistent text-send service.

Existing coverage: deadlines emulator tests already cover closed clients, overdue catch-up, stale tasks and atomic handoff. text-retry covers lost response across turns/finish, authorization and duplicates. pending_text_send covers persisted identity, SDK request fields, auth switching and late draft acknowledgements. Do not duplicate those paths.

Investigate missing client snapshot freshness, expiry enablement and disposal during hydration. Native network/process persistence and SDK transport remain separate device acceptance; deterministic client state tests and backend emulator tests must not be described as device proof.

## Local findings and changes

1. Reproduced a disposed `ValueNotifier` access when profile hydration completed after leaving the room. Mounted checks now stop initialization after each awaited hydration/advance before countdown or subscription work.
2. Reproduced round 3 being replaced by a cached round 1 through the actual Firestore SDK event channel. Cached/pending snapshots now disable text confirmation without replacing the accepted room state. Only authoritative snapshots establish the round/finished high-water mark; an initially cached future round cannot prevent correction by the server.
3. Independent review caught a race introduced by resume refresh: a cached event could invalidate confirmation, then an older server read could enable text again. The regression fails with the revision invalidation removed. Cached/pending events now invalidate outstanding refresh reads as well.

Resume retains one stream and requests an explicit server read. Lifecycle generations and snapshot revisions discard superseded responses. Text sending checks room visibility, confirmation, original absolute deadline and turn eligibility. The existing media controls retain their previous eligibility; no media behavior change is intended. No new pause, surrender, penalty, result mutation or backend deadline change is introduced.

## Coverage and limits

Four new widget tests exercise the real room/input code via mocked native SDK channels: disposal during hydration; cached and initially cached states, pending writes, monotonic rounds, delayed refresh, pause/resume, expired turn, offline completion, result navigation and reentry subscription cancellation; disabled text preserving draft/media controls. Unrelated room media rendering is suppressed in the state scenarios. These tests exercise production Dart logic, but their transport is deterministic, not a physical network or native persistence test.

Existing persistent-send tests and emulator deadline/retry tests remain the evidence for request identity on service recreation, lost acknowledgements, server timing without clients and stale-turn rejection. No new request cache format or account handling is introduced. Remaining device acceptance: airplane-mode and reconnect with two devices, actual process termination/restart, native Firestore cache/listener behavior and server-clock/device-clock skew. A last confirmed turn can remain visible until the SDK detects disconnection; server authorization/deadline validation remains authoritative.

The base and remote setup tip are `00d23ee0af8fd5802862e1282c7ccb87ee502042`. All tests use synthetic local state or `demo-*` emulators. No cloud database, installed APK, credentials, deployment or publication is part of this package. Exact final commands/results and patch hashes are recorded in the accompanying manifest/report.

Independent read-only review (`room_recovery_review`) found no remaining confirmed P1/P2 in this scoped diff after the refresh race regression was fixed. It did not run tests itself. Native listener setup/cancellation while the SDK is still establishing its initial subscription remains a device/SDK limitation, not a guaranteed fix from these Dart tests; resume no longer creates a replacement subscription.
