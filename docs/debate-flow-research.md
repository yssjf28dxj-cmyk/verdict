# Debate Flow Research
## Technical Architecture Document — Verdict Platform

**Status:** PLANMODE — No implementation approved yet
**Date:** 2026-04-01
**Scope:** Upload Grace Lock · Yield Floor

---

## Section 1: Root Cause Analysis — The Upload Loop

### Actual Bug Mechanism

The loop is not a UI glitch — it is a **state desync** caused by a missing `finally` block
in `_sendMediaMessage()`, compounded by a CF timing conflict.

**Sequence that reproduces the freeze:**

```
T-2s  User releases mic → _isUploadingMedia = true
T=0   roundEndsAt expires
T+0s  Client ticker fires → _attemptAdvanceRoundOrFinish() called
T+0s  CF: nowMs >= endMs → round advances → activeSpeakerId changes
T+3s  Upload finishes → sendDebateMessage CF called
T+3s  CF: activeSpeakerId !== uid → throws HttpsError('failed-precondition')
T+3s  Client catch block → shows Retry snackbar
       ↳ BUG: _isUploadingMedia is NEVER reset to false
T+∞   Uploading bar frozen. User cannot type. Session dead.
```

The secondary failure mode (pure network drop) is identical:
`MediaUploadService.uploadVoice()` returns `null` or throws → catch runs → same freeze.

### Two-Layer Fix Required

**Layer 1 — Client (`_sendMediaMessage`):**
A `finally` block that unconditionally resets `_isUploadingMedia = false` regardless of
success or failure path. This is the single-line fix that eliminates the infinite freeze.

**Layer 2 — Server (Grace Period):**
Without this, a legitimate upload that completes at T+3s still gets rejected by the CF
("not your turn"), forcing the user into the retry flow even though the upload succeeded.
The grace window eliminates this rejection for normal-latency uploads.

---

## Section 2: Grace Period Architecture

### Core Principle

A **7-second soft expiry** is baked into server-side logic only.
No extra Firestore reads or writes per message. Zero cost at scale.

### Changes Required (3 touch points)

#### Touch Point A — `sendDebateMessage` CF

Add a grace tolerance check alongside the existing `isRoundActive` guard:

```
CURRENT:  if (!isRoundActive) → reject
ADD:      if (!isRoundActive AND now > roundEndsAt + GRACE_MS) → reject
          if (!isRoundActive AND now <= roundEndsAt + GRACE_MS) → allow (in-flight upload)
```

The grace window only applies when `isRoundActive` has already flipped to `false`
(i.e., the round ended). If the round is still active, no change in behavior.

`GRACE_MS = 7000` (7 seconds)

#### Touch Point B — `autoAdvanceLiveDebates` (scheduled, every 1 min)

```
CURRENT query:  .where('roundEndsAt', '<=', now)
NEW query:      .where('roundEndsAt', '<=', Timestamp.fromMillis(Date.now() - GRACE_MS))
```

This delays the server-side scheduled advance by 7 seconds, giving in-flight uploads
a guaranteed window to resolve. On a 1-minute schedule, the 7s delay is imperceptible
to the debate flow.

#### Touch Point C — `advanceRoundOrFinish` (client-callable CF)

```
CURRENT:  if (nowMs < endMs) → return (no-op)
NEW:      if (nowMs < endMs + GRACE_MS) → return (no-op)
```

Prevents the client ticker from triggering a premature advance during an active upload.
The client adds a matching 7-second delay before calling the CF:

```
Client ticker (remaining <= 0):
  → wait GRACE_DELAY_MS (7s) before calling _attemptAdvanceRoundOrFinish
```

### Grace Period — Edge Case Matrix

| Scenario | Outcome |
|---|---|
| Upload completes at T+3s (4G) | Accepted by CF, advance fires at T+7s ✅ |
| Upload completes at T+6s (3G) | Accepted by CF, advance fires at T+7s ✅ |
| Upload completes at T+8s (slow 3G) | Rejected by CF, user sees Retry button. `_isUploadingMedia` reset by `finally`. ✅ |
| Network drop — upload never completes | `MediaUploadService` timeout (30s) → exception → `finally` resets state ✅ |
| User closes app mid-upload | State is garbage-collected. Advance fires via `autoAdvanceLiveDebates` at next minute tick ✅ |
| Double-tap send during upload | `_isUploadingMedia` guard blocks second send ✅ |

---

## Section 3: Yield Floor Architecture

### Overview

A new Cloud Function `yieldTurn` that allows the active speaker to surrender their
remaining time. The server immediately expires `roundEndsAt`, which both the client
ticker and `autoAdvanceLiveDebates` detect and act on.

### CF: `yieldTurn` — Logic (pseudocode)

```
yieldTurn(debateId):
  1. Verify auth (uid required)
  2. Firestore transaction:
     a. Read debate doc
     b. Validate:
        - status === 'active'
        - isRoundActive === true
        - activeSpeakerId === uid  ← caller must be the active speaker
     c. Write:
        - roundEndsAt = Timestamp.fromMillis(Date.now() - GRACE_MS - 100)
          (placed firmly in the past, past the grace window, so both
           the client ticker and autoAdvanceLiveDebates fire immediately)
        - yieldedAt = FieldValue.serverTimestamp()  ← audit trail
  3. Return { success: true }
  4. Client ticker detects remaining <= 0 on next tick → calls advanceRoundOrFinish
```

**Why set `roundEndsAt` to `now - GRACE_MS - 100ms`?**
The advance CF checks `nowMs >= endMs`. If we set it to `now`, there's a 7-second
delay from the grace window. By setting it to `past the grace window`, the advance
fires on the very next ticker tick (≤ 1 second latency). The opponent sees control
transfer within 1 second of the yield.

### Firestore Fields Added

```
// On the debate document:
yieldedAt: Timestamp | null   // serverTimestamp when last yield occurred
                              // null = no yield yet this round
```

No other schema changes. `roundEndsAt` is already the canonical timer field.

### Client-Side — Yield Button Visibility Rules

```
showYieldButton:
  - status == 'active'
  - isRoundActive == true
  - activeSpeakerId == currentUserId
  - !_isUploadingMedia      ← CRITICAL: see Section 4
  - !_isSendingMessage
  - debateType != 'solo'    ← no yield in practice/solo debates
```

### Yield — Edge Case Matrix

| Scenario | Outcome |
|---|---|
| Normal yield, no pending upload | round transfers within ~1s ✅ |
| Double-tap Yield | Transaction idempotent: second call sees `roundEndsAt` already in past, advance already fired → CF returns no-op ✅ |
| Opponent's device doesn't update | Firestore real-time listener updates `roundEndsAt` → ticker detects 0 → advance fires client-side ✅ |
| Yield during `activeSpeakerId` mismatch (viewer taps) | CF validates `activeSpeakerId === uid` → rejects with `permission-denied` ✅ |
| Both fighters yield simultaneously | Impossible: only `activeSpeakerId` can yield. Second fighter is not the active speaker ✅ |

---

## Section 4: Critical Interaction — Yield While Upload is Pending

This is the most dangerous edge case in the entire feature set.

**Scenario:** Speaker records a voice message, releases, upload starts (`_isUploadingMedia = true`),
then immediately presses Yield.

**Three possible policies:**

| Policy | Behavior | Risk |
|---|---|---|
| **A — Block Yield** | Yield button disabled while `_isUploadingMedia == true`. User must wait for upload to complete or fail. | User stuck if upload hangs on a dead connection. Yield is blocked indefinitely. |
| **B — Cancel & Yield** | Yield cancels the upload, discards the file, surrenders turn immediately. | User loses their recorded argument. Potentially frustrating if accidental. |
| **C — Background Yield** | Yield fires. Upload continues in background. Message saved after round advances. Appears in wrong round's chat. | Confusing UX — message appears after control has shifted to the opponent. Firestore `sendDebateMessage` CF would reject it (no longer active speaker). Same freeze bug as Section 1. |

**Recommended Policy: A (Block Yield)**

Rationale:
- The `finally` block from Layer 1 guarantees that if the upload fails or times out,
  `_isUploadingMedia` resets to `false` and the Yield button becomes available again.
- `MediaUploadService` should enforce a hard timeout (30 seconds) to bound the wait.
- Policy B risks data loss. Policy C reintroduces the exact desync bug we are fixing.
- The blocked-yield state is bounded: 7s grace + 30s upload timeout = max 37s delay.

**Yield button state machine:**

```
IDLE → [start recording] → RECORDING → [release] → UPLOADING → [complete] → IDLE
                                                               → [fail]    → IDLE (via finally)
                                                               → [timeout] → IDLE (via finally)

Yield enabled only in IDLE state.
```

---

## Section 5: Deployment Sequence

When approved for implementation, the order is:

```
1. Add finally block to _sendMediaMessage()          ← hotfix, deploy immediately
2. Update sendDebateMessage CF (grace window)         ← functions deploy
3. Update advanceRoundOrFinish CF (grace window)      ← functions deploy (same build)
4. Update autoAdvanceLiveDebates query                ← functions deploy (same build)
5. Add yieldTurn CF                                   ← functions deploy (same build)
6. Add Yield button to DebateInputBar                 ← flutter build
7. Adjust client ticker delay (7s after remaining=0)  ← flutter build (same)
```

Steps 2–5 must be deployed atomically (one `firebase deploy --only functions` call)
to prevent a window where the grace window is active on the client but not the server.

---

## Critical Questions for Approval

**Q1 — Grace Period Duration:**
7 seconds covers ~97% of uploads on 4G/WiFi. For 3G or rural users with 30s+ upload
times, it does not. The alternative is a Firestore **upload lock** field
(`pendingUpload: { uid, expiresAt: now+30s }`) written at the start of every media
upload and checked by both CFs — but this costs 2 extra Firestore writes per media
message and adds schema complexity.

> **Decision needed:** Accept 7s grace (simplest, limits protection to good connections)
> OR implement the upload lock (full protection, but adds cost + complexity)?

**Q2 — Yield + Upload Interaction Policy:**
Policy A (Block Yield while uploading) is recommended. But it means if a user records
a voice message and the connection drops, they are locked out of Yield for up to 30
seconds (upload timeout). During that window, they cannot yield and cannot send —
they can only wait or the round expires naturally.

> **Decision needed:** Is 30-second max blocked-yield window acceptable UX for Verdict's
> target users, OR should we implement Policy B (cancel upload + yield) with an explicit
> confirmation dialog ("Cancel your message and yield?") to prevent accidental data loss?
