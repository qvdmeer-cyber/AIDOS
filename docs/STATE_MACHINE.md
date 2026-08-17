# State machine

AIDOS uses explicit states so neither GPT nor Codex can infer permission to continue merely from conversation context.

## External preparation gate

Preparation is owned by AIDOS-Builder/AIDOS-Contracts but is a hard prerequisite for private AIDOS runtime:

```text
NEW_PROJECT
PROJECT_BASELINE_ACCEPTED
→ AIDOS runtime eligible

EXISTING_PROJECT
PROJECT_BASELINE_ACCEPTED
→ CURRENT_PRODUCT_STATE_REQUIRED
→ DISCOVERY_CLOSURE
→ CURRENT_PRODUCT_STATE_ACCEPTED
→ AIDOS runtime eligible
```

`CURRENT_PRODUCT_STATE_ACCEPTED` means accepted under the current required CPS/discovery contract and with the material product graph closed. An accepted historical CPS under weaker rules does not pass the current gate.

## Discovery refresh states

If newer evidence or stronger closure contracts reveal missing product branches:

```text
CURRENT_PRODUCT_STATE_ACCEPTED
→ DISCOVERY_REFRESH_REQUIRED
→ AIDOS-Builder refresh
→ deterministic Discovery Closure
→ CURRENT_PRODUCT_STATE_ACCEPTED (new CPS lineage)
```

Examples that require refresh include:

- a newly identified `FIRST_PARTY_MATERIAL` component not covered by CPS;
- a known public/passive runtime that was not observed;
- unresolved material source/runtime references;
- evidence showing the bound CPS was materially stale/wrong.

Existing evidence and prior accepted CPS are preserved. Refresh discovers only missing branches unless broader truth has become unreliable.

Private AIDOS must not compensate by allowing Definition/Worker to reconstruct the missing product state informally.

## Definition states

```text
DISCOVERY
→ OPEN_QUESTIONS
→ PROPOSED
→ USER_REVIEW
→ ACCEPTED

ACCEPTED
→ CONTRADICTION_FOUND
→ REOPENED
→ OPEN_QUESTIONS
→ ...
```

Here `DISCOVERY` is goal/decision elicitation inside Definition; it is **not Existing Project Discovery**.

Only `ACCEPTED` may authorize creation of a new execution for that Definition version.

## Project/execution states

```text
IDLE
→ TASK_READY
→ CODEX_RUNNING
→ TERMINAL_PENDING
├─ deterministic execution evidence PASS → REVIEW_READY
└─ evidence missing/failed              → EXECUTION_VALIDATION_FAILED
→ GPT_REVIEWING

GPT_REVIEWING
├─ PASS                       → IDLE / next accepted goal
├─ REPAIR                     → TASK_READY
├─ BLOCKER                    → WAITING_USER
├─ DISCOVERY_REFRESH_REQUIRED → DISCOVERY_REFRESH_REQUIRED
├─ WAITING_INTERACTIVE_SESSION→ WAITING_INTERACTIVE_SESSION
├─ CONTRADICTION              → WAITING_DEFINITION
└─ RELEASE_READY              → release lifecycle / genuine release authority gate
```

`DISCOVERY_REFRESH_REQUIRED` is not a product-decision gate. It means current-state preparation no longer satisfies the required closure invariant.

Revision-scoped dispatch metadata may be rebound while remaining in `TASK_READY` through a
dedicated dispatch-binding action/event. That rebinding is not a state transition and does not
relax the `TASK_READY -> TASK_READY` prohibition.

## Launch Definition states

```text
LAUNCH_DISCOVERY
→ LAUNCH_PROPOSED
→ LAUNCH_USER_REVIEW
→ LAUNCH_ACCEPTED
→ RELEASE_SCOPE_FROZEN
```

New findings after freeze are:

```text
LAUNCH_BLOCKER
POST_LAUNCH
EVIDENCE_REQUIRED
```

A proven blocker or deliberate human delay may explicitly reopen:

```text
RELEASE_SCOPE_FROZEN / RELEASE_READY
→ LAUNCH_REOPEN_REQUESTED
→ LAUNCH_REOPENED
→ LAUNCH_USER_REVIEW
→ LAUNCH_ACCEPTED
→ RELEASE_SCOPE_FROZEN
```

## Release-ready invariant

When all accepted Launch Definition criteria are PASS and no unresolved `LAUNCH_BLOCKER` remains, default forward state is:

```text
RELEASE_READY
```

AIDOS must not return to feature discovery merely because another improvement is imaginable.

## Additional infrastructure states

- `QUEUED` — valid task waiting for local execution slot;
- `WAITING_INTERACTIVE_SESSION` — work ready but supervised policy blocks desktop GPT activation;
- `CONTEXT_ROTATION_REQUIRED` — current GPT/Codex context must not resume;
- `RECOVERY_REQUIRED` — durable state requires reconciliation.
- `REVIEW_READY` — execution evidence passed; review transport has not yet been published.
- `GPT_REVIEWING` — review transport is published, the assignment envelope is available and a
  Worker/GPT consumer is permitted to return a bound response.
- `ABANDONED` is a terminal **review transport status**, not a project state. It records an
  explicit reason and exact review/execution/manifest identity for an unconsumed rejected review;
  package and rejected-response evidence remain preserved. It is permitted only when no bridge
  response, accepted response, decision, consume acknowledgement, or cleanup exists.
- `REVIEW_RECOVERY_REQUIRED` — a published review needs explicit bridge recovery before it can be
  consumed safely.
- `EXECUTION_VALIDATION_FAILED` — Codex terminated, but declared deterministic execution evidence is absent or failed; session and terminal evidence remain available for a bounded repair revision.
- `EXECUTION_DISPATCH_BOUND` — revision-scoped dispatch metadata rebound while the project remains in `TASK_READY`.

## Execution terminal outcomes

Execution Agent may terminate only as:

- `TER_REVIEW`;
- `CONTROLLED_GATE`;
- `BLOCKER`;
- `RUNTIME_STOP`;
- `REQUIREMENT_CONTRADICTION`.

Ordinary build/test/runtime failures are not terminal while safe useful technical steps remain.

`DISCOVERY_REFRESH_REQUIRED` and `RELEASE_READY` are Worker/review transitions, not self-declared Execution Agent outcomes.

Review outcomes are distinct from top-level project states. The durable review record stores the outcome, while the project state is driven deterministically by that outcome:

```text
PASS                       → IDLE
REPAIR                     → TASK_READY
BLOCKER                    → WAITING_USER
DISCOVERY_REFRESH_REQUIRED → DISCOVERY_REFRESH_REQUIRED
WAITING_INTERACTIVE_SESSION→ WAITING_INTERACTIVE_SESSION
```

An explicit review abandonment never fabricates one of these outcomes and never changes project
state. A valid `ABANDONED` transport closure is terminal for project-wide reconciliation; a
missing, mismatched, or tampered closure remains fail-closed recovery work.

## Fail-closed transitions

A transition is rejected when project, project mode, preparation binding, Definition version, execution ID/revision, root, branch or required commit binding does not match canonical state.

For `EXISTING_PROJECT`, preparation binding includes:

```text
accepted CPS id/commit
CPS contract version = 0.2.0
discovery catalog version = 0.2.0
discovery state = ACCEPTED
open discovery blockers = 0
```

For release-scoped work, Launch Definition/release identity is additionally bound when runtime persistence is implemented.
