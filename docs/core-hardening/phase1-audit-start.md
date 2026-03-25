# Phase 1 Execution Start - Core Architecture Audit (In Progress)

Status: started
Date: 2026-03-21

## Scope for Phase 1 execution
- Map all lifecycle files for debate engine
- Confirm current schema variants and aliases
- Confirm all critical callables and triggers
- Produce risk-ranked inconsistency list

## Initial confirmed core files
- Backend:
  - functions/src/index.ts
  - firestore.rules
- Flutter lifecycle/presentation:
  - lib/screens/debate_room_screen.dart
  - lib/screens/lobby_screen.dart
  - lib/screens/create_debate_screen.dart
  - lib/screens/home_screen.dart
  - lib/widgets/debate_messages_list.dart
- Flutter models/services:
  - lib/models/debate.dart
  - lib/models/debate_lobby.dart
  - lib/services/referee_service.dart
  - lib/services/lobby_service.dart
  - lib/services/debate_timer_service.dart
  - lib/utils/debate_error_mapper.dart

## Initial schema inconsistency snapshot
1. Status aliases still exist in readers (`live` mapped to `active` in some places).
2. Participant identity still dual (`creatorId/opponentId` and `fighter1/fighter2`).
3. Round index still dual (`roundIndex/currentRound`, legacy `round` reads remain).
4. Duration still dual (`roundDurationSeconds/durationSeconds`, legacy reads remain).
5. Client fallback transaction write still exists for accept path in debate room.

## Critical callable map (authoritative paths)
- createDebate
- acceptDebateInvite
- sendDebateMessage
- applyPenalty
- castVote
- getMyVoteStatus
- advanceRoundOrFinish
- cancelDebateChallenge

## Immediate next execution tasks
1. Add backend flag scaffolding and telemetry counters.
2. Extract centralized validator module and transition policy module.
3. Remove client direct accept fallback write path and switch to retry-only.
4. Add canonical DTO mapper for backend action handlers.

## Progress updates
- 2026-03-21: Task 3 completed for accept flows in UI.
  - `lib/screens/debate_room_screen.dart`: removed Firestore transaction fallback write in `_acceptPendingDebate`; replaced with retry-only callable path.
  - `lib/screens/lobby_screen.dart`: removed `_acceptInviteFallbackDirect` transaction write path; `_acceptInvite` now retries callable once for transient backend errors.
- Result: client no longer mutates debate state directly during accept fallback flows.

- 2026-03-21: Next authority-cut batch (non-accept lifecycle writes).
  - `lib/screens/create_debate_screen.dart`: removed direct create fallback write; create flow is callable + retry only.
  - `lib/screens/lobby_screen.dart`: removed direct delete fallback in cancel flow; cancel is callable + retry only.
  - `lib/screens/debate_room_screen.dart`: removed `_ensureServerStart` transaction patch path (client no longer writes round/speaker bootstrap).
  - `lib/services/referee_service.dart`: `finishDebate` now routes through backend callable instead of direct status/winner write.
  - `lib/services/lobby_service.dart`: `startDebate` now uses backend `createDebate` callable instead of direct `debates.add(...)` lifecycle write.
  - `functions/src/domain/debate/guards.ts`: expanded centralized guard coverage (`create`, `cancel`, `advance/finish`, `message`, `vote`, `accept`).
  - `functions/test/guards.test.js`: added permission matrix and guard coverage tests (11 passing).
  - `functions/src/index.ts` + `lib/services/admin_service.dart`: admin debate deletion routed through backend callable `adminDeleteDebate`.
  - `lib/services/stats_service.dart`: legacy finalize lifecycle write removed; finalize now delegates to backend callable `advanceRoundOrFinish`.
  - Result: no remaining direct client writes to debate lifecycle fields.

## Risks to monitor from first coding batch
- accept flow regressions on older documents
- viewer/fighter role render mismatch in room/home
- increase in invalid-state rejects during strict guard introduction
