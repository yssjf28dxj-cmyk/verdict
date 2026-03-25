# VERDICT Core Hardening - Concrete Execution Plan

## 1) Step-by-step refactor order

### Step 0 - Freeze + guardrails (Day 0)
- Introduce feature flags in backend config:
  - `core.canonicalWriteEnabled` (default false)
  - `core.legacyReadEnabled` (default true)
  - `core.legacyWriteEnabled` (default true)
  - `core.strictTransitionsEnabled` (default false)
- Add schema marker fields to debate writes:
  - `schemaVersion: 2`
  - `migrationState: pre_backfill | backfilled | verified`
- Add read/write hit counters for legacy aliases.

### Step 1 - Canonical DTO and mappers (Backend first)
- Add canonical debate DTO and mapper layer in Functions:
  - `domain/debate/types.ts`
  - `domain/debate/mappers.ts`
  - `domain/debate/normalizer.ts`
- Keep storage still in existing fields, but route all action handlers through DTO mapping.
- No behavior change yet, only canonical in-memory model.

### Step 2 - Centralized validators and state machine
- Create centralized guard helpers:
  - `canCreateDebate`, `canAcceptDebate`, `canSendMessage`, `canVote`, `canAdvanceRound`, `canFinishDebate`, `canCancelDebate`.
- Add explicit transition table and enforcement in one module.
- Rewrite first in this order:
  1. `acceptDebateInvite`
  2. `sendDebateMessage`
  3. `castVote`
  4. `advanceRoundOrFinish`
  5. `cancelDebateChallenge`
  6. `createDebate`
  7. `applyPenalty`

### Step 3 - Canonical write enablement
- Turn on `core.canonicalWriteEnabled=true` in dev/stage.
- All critical callables write canonical fields only plus compatibility mirrors.
- Keep `legacyReadEnabled=true` and `legacyWriteEnabled=true` for one short window.

### Step 4 - Client canonical DTO adoption
- Introduce canonical DTO in Flutter domain/data layers and use mapper from snapshots.
- Update readers in this order:
  1. debate room
  2. lobby
  3. home/feed cards
  4. result/profile history
- Keep normalizer enabled so old docs still render.

### Step 5 - Disable legacy writes
- Set `core.legacyWriteEnabled=false` in backend first.
- Remove fallback client direct writes for accept/create critical state mutation.
- Any client fallback becomes request/retry only, not state mutation.

### Step 6 - Backfill start
- Run dry-run migration callable to estimate old docs and conflicts.
- Run batched backfill callable:
  - idempotent by document marker
  - cursor-based pagination
  - conflict bucket for manual review
- Mark migrated docs `migrationState=backfilled`.

### Step 7 - Strict transitions on
- Enable `core.strictTransitionsEnabled=true` in stage, then production.
- Reject invalid transitions and legacy conflicting writes.

### Step 8 - Legacy reads off
- After telemetry shows near-zero legacy hits, set `core.legacyReadEnabled=false`.
- Remove compatibility aliases from codebase.

### Step 9 - Verification + cleanup
- Post-migration verifier callable checks invariants and schema uniformity.
- Remove dead fields and old mapper branches.

## 2) Blast radius analysis

### Step 1-2 (DTO + validators)
- Screens at risk:
  - debate room, lobby, home cards (status/role rendering)
- Temporarily unstable flows:
  - accept invite and round advance if mapper mismatch exists
- Synchronous update required:
  - backend reason-code mapping in client error mapper
- Firestore incompatibility risk:
  - low (read-only compatibility phase)

### Step 3 (canonical writes)
- Screens at risk:
  - any reader using legacy-only fields (currentRound, timeSeconds, live)
- Temporarily unstable flows:
  - waiting->active UI transitions if status normalization missing
- Synchronous update required:
  - debate room + home feed status/round readers
- Firestore incompatibility risk:
  - medium for stale clients not using normalizer

### Step 4 (client adoption)
- Screens at risk:
  - debate room, lobby, result screen, home feed
- Temporarily unstable flows:
  - participant role detection, accept button visibility
- Synchronous update required:
  - all participant checks to canonical participant model
- Firestore incompatibility risk:
  - low if legacyReadEnabled true

### Step 5 (legacy writes off)
- Screens at risk:
  - create and accept paths where client fallback writes still exist
- Temporarily unstable flows:
  - offline/degraded network accept flow
- Synchronous update required:
  - fallback UI changed to retry callables only
- Firestore incompatibility risk:
  - medium for outdated app versions

### Step 6-7 (backfill + strict transitions)
- Screens at risk:
  - old debates with partial fields may fail until migrated
- Temporarily unstable flows:
  - accessing very old debates during active backfill
- Synchronous update required:
  - migration verifier dashboard + error mapper
- Firestore incompatibility risk:
  - high if conflicts ignored; mitigated with conflict bucket

### Step 8-9 (legacy read removal)
- Screens at risk:
  - only old builds or uncaptured edge readers
- Temporarily unstable flows:
  - opening un-migrated deep-linked old debate
- Synchronous update required:
  - production gate requires zero legacy-hit window
- Firestore incompatibility risk:
  - low after verifier pass

## 3) Rollback strategy

### Rollback triggers
- invalid-transition reject rate spikes above threshold
- accept/vote failures exceed baseline SLA
- migration conflict bucket growth exceeds threshold

### Rollback actions
1. Set flags:
   - `core.strictTransitionsEnabled=false`
   - `core.legacyReadEnabled=true`
   - `core.legacyWriteEnabled=true` (temporary emergency only)
2. Keep canonical writes on unless critical corruption risk is detected.
3. Pause backfill job runner.
4. Route failed docs to conflict review queue.

### Recovery mode
- Dual-read mode restored immediately via flag.
- Dual-write only allowed as short emergency window with audit log.
- All emergency toggles must emit audit event with operator + reason.

### Version markers
- `schemaVersion`
- `migrationState`
- `normalizerVersion`
- `transitionPolicyVersion`

## 4) Telemetry checkpoints

### Migration success metrics
- `migration.docs.scanned`
- `migration.docs.backfilled`
- `migration.docs.conflicts`
- `migration.docs.verified`

### Legacy usage decay
- `legacy.read.hit.count` by field alias
- `legacy.write.blocked.count`
- `legacy.write.attempt.count`

### Transition safety
- `debate.transition.attempt.count`
- `debate.transition.reject.count`
- `debate.transition.invalid_state.count`
- `debate.transition.invalid_transition.count`

### Reject-rate guardrails
- `action.accept.reject.rate`
- `action.vote.reject.rate`
- `action.message.reject.rate`
- `action.advance.reject.rate`
- SLO: no sustained regression > 20% from pre-refactor baseline for 24h.

### Idempotency and race checks
- `action.accept.duplicate_detected`
- `action.vote.duplicate_detected`
- `action.finish.repeated_noop`
- `action.advance.stale_noop`

## 5) Refactor freeze rule

- No new product features during core hardening.
- No UI experiments or design polish tracks in parallel.
- No voice/live/media/feed growth work during this window.
- Only allowed scope:
  - canonical schema
  - validators/state machine
  - migration and compatibility
  - tests and observability

## 6) Execution start gate

Phase 1 execution starts only after:
- this plan is accepted
- flags and telemetry counters are committed
- baseline metrics snapshot is saved
