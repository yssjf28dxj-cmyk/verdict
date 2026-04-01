# Debate Flow — Implementation Tasks
## Verdict Platform · Approved Architecture

**Approved:** 2026-04-01
**Decisions locked:**
- Grace Period: 7s (`GRACE_MS = 7000`), no upload lock
- Yield + Upload: Policy B — cancel with confirmation dialog

**Execution rule:** Tasks run in strict order within each phase.
Cross-phase dependencies are marked. No task is started until the previous is complete and its DoD is verified.

---

## PHASE 0 — Hotfix (Deploy Independently, No Dependencies)

### TASK-001 · `finally` block in `_sendMediaMessage()`

**File:** `lib/screens/debate_room_screen.dart`

**What:** Add a `finally` block to `_sendMediaMessage()` that unconditionally executes
`if (mounted) setState(() { _isUploadingMedia = false; })`.
Remove any existing `setState` calls for `_isUploadingMedia = false` inside the `try`
and `catch` blocks to avoid double-setState.

**Definition of Done:**
- [ ] `_isUploadingMedia` is reset in `finally`, not in `try` or `catch`
- [ ] Manual test: kill network mid-upload → uploading bar disappears, input bar returns
- [ ] Manual test: upload succeeds → uploading bar disappears, message appears
- [ ] Manual test: CF rejects message (wrong turn) → uploading bar disappears, snackbar shown
- [ ] `flutter analyze` → 0 issues

**Deployable:** Yes, standalone Flutter build. No CF changes required.

---

## PHASE 1 — Server Grace Window (All 4 tasks deploy in one `firebase deploy --only functions`)

> ⚠️ Tasks 002–005 must be deployed atomically in a single functions build.
> Deploying them partially creates a window of inconsistency.

### TASK-002 · Define `GRACE_MS` constant in `functions/src/index.ts`

**File:** `functions/src/index.ts`

**What:** Add a single module-level constant:
```
const UPLOAD_GRACE_MS = 7_000;
```
Place it near the top of the file alongside other constants.
All subsequent tasks reference this constant — no magic numbers.

**Definition of Done:**
- [ ] One constant defined, named `UPLOAD_GRACE_MS`, value `7000`
- [ ] No other code changed in this task
- [ ] `npx tsc --noEmit` → 0 errors

---

### TASK-003 · Grace window in `sendDebateMessage` CF

**File:** `functions/src/index.ts` — function `sendDebateMessage`

**What:** The CF currently rejects messages when `isRoundActive === false`.
Add a secondary check: if `isRoundActive` is false but `roundEndsAt` is present
and `Date.now() <= roundEndsAt.toDate().getTime() + UPLOAD_GRACE_MS`,
allow the message through.

Logic in plain English:
```
if round is not active:
    if roundEndsAt exists AND now <= roundEndsAt + GRACE:
        allow (in-flight upload)
    else:
        reject with 'Round has ended'
```

**Definition of Done:**
- [ ] Messages sent within 7s after round expiry are accepted by the CF
- [ ] Messages sent >7s after round expiry are rejected with a clear error
- [ ] Messages during an active round are unaffected (no regression)
- [ ] `UPLOAD_GRACE_MS` constant is used, no magic number `7000`
- [ ] `npx tsc --noEmit` → 0 errors

---

### TASK-004 · Grace window in `advanceRoundOrFinish` CF

**File:** `functions/src/index.ts` — function `advanceRoundOrFinish`

**What:** The CF currently checks `if (nowMs < endMs) return` (no-op if round not yet expired).
Change to: `if (nowMs < endMs + UPLOAD_GRACE_MS) return`.
This prevents a client-triggered advance from firing during the grace window.

**Definition of Done:**
- [ ] CF returns a no-op when called within 7s of `roundEndsAt`
- [ ] CF proceeds with advance when called after `roundEndsAt + 7s`
- [ ] Existing advance logic (round increment, fighter swap, finish detection) is unchanged
- [ ] `npx tsc --noEmit` → 0 errors

---

### TASK-005 · Grace window in `autoAdvanceLiveDebates` scheduled CF

**File:** `functions/src/index.ts` — function `autoAdvanceLiveDebates`

**What:** The Firestore query currently selects debates where `roundEndsAt <= now`.
Change to: `roundEndsAt <= Timestamp.fromMillis(Date.now() - UPLOAD_GRACE_MS)`.
This delays server-side auto-advance by 7 seconds, matching the client grace window.

**Definition of Done:**
- [ ] Firestore query uses `now - UPLOAD_GRACE_MS` as the threshold
- [ ] `UPLOAD_GRACE_MS` constant is used, no magic number
- [ ] Existing advance logic inside the loop is unchanged
- [ ] `npx tsc --noEmit` → 0 errors
- [ ] Firestore index for `(status, roundEndsAt)` already exists (confirmed in project)

---

## PHASE 2 — Client-Side Grace Delay (Flutter, depends on PHASE 1 being deployed)

### TASK-006 · Client ticker delay before calling `advanceRoundOrFinish`

**File:** `lib/screens/debate_room_screen.dart`

**What:** In `_startRoundCountdownTicker()`, when `remaining <= 0` and
`_shouldAttemptAdvanceFromClient` returns true, add a 7-second delay before calling
`_attemptAdvanceRoundOrFinish()`. This prevents the client from racing the server
during the grace window.

Use a one-shot `Future.delayed(const Duration(seconds: 7), ...)` guarded by:
- `if (!mounted) return` after the delay
- `if (movedToResult) return` after the delay
- The existing `_advanceAttemptToken` mechanism to cancel stale delayed calls

**Definition of Done:**
- [ ] `_attemptAdvanceRoundOrFinish()` is not called until 7s after `remaining == 0`
- [ ] If the user navigates away during the 7s delay, the delayed call is cancelled (no crash)
- [ ] If the round advances server-side (e.g., via auto-advance) during the 7s, the
      client call becomes a no-op (existing idempotency handles this)
- [ ] `flutter analyze` → 0 issues

---

## PHASE 3 — Yield Floor Feature (depends on PHASE 1 deployed, PHASE 2 complete)

### TASK-007 · `yieldTurn` Cloud Function

**File:** `functions/src/index.ts`

**What:** Add a new exported callable CF `yieldTurn`.

Logic:
1. Authenticate caller (uid required)
2. Read debate document inside a Firestore transaction
3. Validate:
   - `status === 'active'`
   - `isRoundActive === true`
   - `activeSpeakerId === uid` (caller must be the speaker)
4. Write to debate doc:
   - `roundEndsAt = Timestamp.fromMillis(Date.now() - UPLOAD_GRACE_MS - 100)`
     (places it firmly past the grace window so advance triggers on next tick)
   - `yieldedAt = FieldValue.serverTimestamp()`
5. Return `{ success: true }`

Error codes to use:
- `unauthenticated` if not signed in
- `not-found` if debate doesn't exist
- `failed-precondition` if validation fails (wrong speaker, round inactive, debate finished)
- `permission-denied` if caller is not `activeSpeakerId`

**Definition of Done:**
- [ ] CF exported and callable
- [ ] Transaction is used (no TOCTOU race on `activeSpeakerId`)
- [ ] All 4 error cases return descriptive `HttpsError`
- [ ] `yieldedAt` written with `FieldValue.serverTimestamp()` (not `Date.now()`)
- [ ] `roundEndsAt` set to `now - UPLOAD_GRACE_MS - 100` (not `now`)
- [ ] Double-tap is idempotent: second call sees round already advanced, returns gracefully
- [ ] `npx tsc --noEmit` → 0 errors

---

### TASK-008 · Yield button state management in `DebateInputBar`

**File:** `lib/widgets/debate_input_bar.dart` (extracted widget from Phase 6B)

**What:** Add a Yield button to the input bar widget.

Visibility / enabled rules (all must be true):
- `isMyTurn == true`
- `isRoundActive == true`
- `!isRecording`
- `!isUploading`
- `!isSendingMessage`
- `debateType != 'solo'`

Button appearance:
- Icon: `Icons.skip_next` or similar "pass" icon
- Label: short text (e.g., "Уступить")
- Color: warning amber (not destructive red — yield is intentional, not dangerous)
- Disabled state: 50% opacity, no tap handler

Add callback `onYield: VoidCallback?` to the widget's parameter list.

**Definition of Done:**
- [ ] Button renders only when all 5 conditions are satisfied
- [ ] Button is visually distinct from Send and Mic buttons
- [ ] Button is invisible (not just disabled) when `!isMyTurn`
- [ ] Button is disabled (greyed) when `isUploading || isRecording || isSendingMessage`
- [ ] `debateType == 'solo'` hides the button entirely
- [ ] `onYield` callback is non-null only when button is enabled
- [ ] `flutter analyze` → 0 issues

---

### TASK-009 · Yield confirmation dialog (Policy B)

**File:** `lib/screens/debate_room_screen.dart`

**What:** Implement `_onYieldPressed()` method that is passed as `onYield` to `DebateInputBar`.

Two distinct flows depending on state:

**Flow A — No pending upload (`!_isUploadingMedia && !_isRecording`):**
Show a simple confirmation `AlertDialog`:
- Title: "Уступить слово?"
- Body: "Ваше оставшееся время будет передано оппоненту."
- Actions: "Отмена" (dismiss) | "Уступить" (call CF)

**Flow B — Pending upload (`_isUploadingMedia == true`):**
Show a warning `AlertDialog`:
- Title: "Отменить отправку и уступить?"
- Body: "Ваше голосовое сообщение ещё загружается. Если уступить сейчас, оно будет отменено."
- Actions: "Продолжить загрузку" (dismiss) | "Отменить и уступить" (cancel upload + call CF)

Cancel upload logic (Flow B only):
- Set `_isUploadingMedia = false` (the `finally` block from TASK-001 will also fire, harmlessly)
- The upload's CF call (`sendDebateMessage`) will fail after yield since the round is over — this is acceptable and handled by the existing catch block

After confirmation in either flow:
- Set `_isYieldingTurn = true` (loading state)
- Call `yieldTurn` CF
- On success: `_isYieldingTurn = false` (round advance detected via Firestore listener)
- On error: `_isYieldingTurn = false`, show error snackbar

**Definition of Done:**
- [ ] Flow A dialog shown when no upload is pending
- [ ] Flow B dialog shown with explicit warning when upload is in progress
- [ ] "Cancel and yield" correctly interrupts the upload flow
- [ ] `_isYieldingTurn` loading state disables Yield button during CF call
- [ ] Error from CF shown in snackbar, state fully reset on failure
- [ ] Dialog is dismissed cleanly on "Cancel" with no state change
- [ ] `flutter analyze` → 0 issues

---

### TASK-010 · Wire `onYield` in `DebateRoomScreen` and pass `isRoundActive`

**File:** `lib/screens/debate_room_screen.dart`

**What:** Connect `DebateInputBar` to the new yield logic. Pass the new required
props that TASK-008 added to the widget:

```
DebateInputBar(
  ...existing props...
  isRoundActive: isRoundActive,
  debateType: debateType,
  onYield: _onYieldPressed,
)
```

**Definition of Done:**
- [ ] All new `DebateInputBar` props are passed correctly from screen state
- [ ] `onYield` passes `_onYieldPressed` from TASK-009
- [ ] Hot restart shows Yield button when it's the user's active turn
- [ ] `flutter analyze` → 0 issues

---

## PHASE 4 — Integration Verification (No new code — testing only)

### TASK-011 · End-to-end upload grace window test

**What:** Manual test on device or emulator.

Test procedure:
1. Start a debate with a short round timer (30s)
2. At T-3s (3 seconds before timer): start recording a voice message
3. At T-0s: release mic (upload begins)
4. Observe: uploading bar visible, round timer hits zero
5. Observe: round does NOT advance for 7 seconds
6. After upload completes: message appears in chat, THEN round advances

**Definition of Done:**
- [ ] Message sends successfully when upload starts ≤7s before round end
- [ ] Round advance is delayed until after upload resolves
- [ ] No frozen `_isUploadingMedia` state after any outcome

---

### TASK-012 · End-to-end yield flow test

**What:** Manual test on two devices (or two simulator instances).

Test procedure:
1. Start a debate (2 fighters, 60s rounds)
2. Fighter 1 is active speaker — verify Yield button is visible
3. Fighter 2 verifies Yield button is NOT visible (not their turn)
4. Fighter 1 taps Yield → confirmation dialog appears → confirms
5. Observe on Fighter 2's device: turn transfers within ~1s
6. Repeat: Fighter 1 records voice, releases (upload starts), taps Yield
7. Observe: Flow B warning dialog appears
8. Confirm "Отменить и уступить"
9. Observe: upload cancelled, turn transfers

**Definition of Done:**
- [ ] Turn transfer observed within 2s of yield confirmation on both devices
- [ ] Flow B dialog correctly warns about in-progress upload
- [ ] After yield, Yield button disappears from Fighter 1 and appears on Fighter 2
- [ ] Firestore `yieldedAt` field is written with a valid server timestamp

---

## Deployment Checklist

```
[ ] TASK-001  flutter build (hotfix — deploy first, standalone)
[ ] TASK-002  \
[ ] TASK-003   |
[ ] TASK-004   |— single: cd functions && npm run build
[ ] TASK-005  /         firebase deploy --only functions
[ ] TASK-007  /

[ ] TASK-006  \
[ ] TASK-008   |— single: flutter build (after functions deploy confirmed)
[ ] TASK-009   |
[ ] TASK-010  /

[ ] TASK-011  manual QA
[ ] TASK-012  manual QA
```

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Grace window too short for target users on slow connections | Low | Medium | Monitor CF error rate on `sendDebateMessage` after deploy; raise `UPLOAD_GRACE_MS` if >5% rejection rate |
| `yieldTurn` transaction contention on high-traffic debates | Low | Low | Transaction retries automatically; CF idempotent |
| Client ticker fires advance before 7s delay completes | Low | Low | `_advanceAttemptToken` invalidates stale delayed calls |
| User confirms Flow B yield but upload already finished | Low | Low | `sendDebateMessage` CF will reject (round ended); `finally` resets state gracefully |
