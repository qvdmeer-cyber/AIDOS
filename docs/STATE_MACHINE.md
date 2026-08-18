# State machine

AIDOS uses explicit durable states so no GPT/Codex session can infer permission to continue from conversation context.

## Ownership of transitions

Actors do not directly transition other actors.

```text
AIDOS
→ actor activation
→ durable result/event/request
→ AIDOS validates/reconciles
→ next state + next actor
```

The current Worker/Definition/Execution actors may recommend outcomes, but the runtime/Bridge owns application of valid transitions.

## External preparation gate

Preparation remains owned by AIDOS-Builder/AIDOS-Contracts:

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

Historical CPS under weaker closure rules does not pass the current gate.

## Discovery refresh

```text
CURRENT_PRODUCT_STATE_ACCEPTED
→ DISCOVERY_REFRESH_REQUIRED
→ AIDOS-Builder refresh
→ deterministic Discovery Closure
→ CURRENT_PRODUCT_STATE_ACCEPTED (new lineage)
```

Missing material first-party components, omitted observable runtime or materially stale CPS trigger refresh rather than informal Definition/Worker discovery.

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

Here `DISCOVERY` means Definition elicitation, not Existing Project Discovery. Only `ACCEPTED` authorizes execution planning.

## Current project/execution states

```text
IDLE
→ TASK_READY
→ CODEX_RUNNING
→ TERMINAL_PENDING
├─ deterministic evidence PASS → REVIEW_READY
└─ evidence failed/missing     → EXECUTION_VALIDATION_FAILED
→ GPT_REVIEWING

GPT_REVIEWING
├─ PASS                       → IDLE / next accepted goal
├─ REPAIR                     → TASK_READY
├─ BLOCKER                    → WAITING_USER
├─ DISCOVERY_REFRESH_REQUIRED → DISCOVERY_REFRESH_REQUIRED
├─ WAITING_INTERACTIVE_SESSION→ WAITING_INTERACTIVE_SESSION
├─ CONTRADICTION              → WAITING_DEFINITION
└─ RELEASE_READY              → release lifecycle
```

These proven single-execution semantics remain valid while workstream orchestration is introduced above them.

`WAITING_USER` remains the current top-level state. A durable Human Input Request with `status=WAITING` records the exact reason/question/binding behind the wait.

## Workstream state projection

`schemas/workstream.schema.json` defines a project-internal workstream projection:

```text
PLANNED
→ READY
→ THINKING
→ EXECUTING
→ VALIDATING
→ WAITING_INTEGRATION
→ INTEGRATED
```

Side states include `BLOCKED`, `WAITING_HUMAN`, `WAITING_DEPENDENCY`, `PAUSED` and `STOPPED`.

A workstream state does not replace the current top-level project state until a future runtime version explicitly implements multi-workstream projection. It is an additive architecture contract.

Parallel workstreams may complete execution independently, but the project cannot claim integrated success until applicable integration gates pass.

## Human Input Request lifecycle

```text
request WAITING
→ human response submitted through authorized channel
→ AIDOS validates exact project/workstream/Definition/execution binding
→ request RESOLVED
→ event persisted
→ AIDOS determines next actor
```

A session disappearance does not cancel or recreate the request.

## Control-intent lifecycle

External control intent never forces a state directly:

```text
RECEIVED
→ ACCEPTED | REJECTED
→ APPLIED | FAILED
```

Examples are `RUN`, `PAUSE`, `RESUME`, `SAFE_STOP`, `QUERY_STATUS`, `SUBMIT_HUMAN_INPUT`, `REQUEST_RECOVERY`.

Pause/safe-stop are safe-boundary orchestration requests, not raw process-kill commands. General remote control runtime support is not yet implemented; current supervised-session semantics remain authoritative meanwhile.

## Launch states

```text
LAUNCH_DISCOVERY
→ LAUNCH_PROPOSED
→ LAUNCH_USER_REVIEW
→ LAUNCH_ACCEPTED
→ RELEASE_SCOPE_FROZEN
```

New findings after freeze are `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`. When all accepted criteria pass with no blocker, default forward state is `RELEASE_READY`.

## Infrastructure states and transport statuses

Current additional states include:

- `QUEUED`;
- `WAITING_INTERACTIVE_SESSION`;
- `CONTEXT_ROTATION_REQUIRED`;
- `RECOVERY_REQUIRED`;
- `REVIEW_READY`;
- `GPT_REVIEWING`;
- `EXECUTION_VALIDATION_FAILED`.

A binding-valid actor result that fails deterministic **pre-application semantic validation** is preserved as evidence and its actor transport is terminalized as `FAILED` with an `ACTOR_RESULT_REJECTED` event. This terminal status removes the rejected attempt from the pending scheduler set so AIDOS can issue a fresh exact-bound assignment. Infrastructure or post-application consumer failures remain `CONSUME_ERROR` and are not silently reclassified as semantic rejection.

`ABANDONED` remains a terminal **review transport status**, not a project/workstream state. It never fabricates a review outcome.

Revision-scoped dispatch rebinding may occur while remaining `TASK_READY`; it is not a general self-transition permission.

## Execution terminal outcomes

Execution Agent may terminate only as:

- `TER_REVIEW`;
- `CONTROLLED_GATE`;
- `BLOCKER`;
- `RUNTIME_STOP`;
- `REQUIREMENT_CONTRADICTION`.

Ordinary technical failures remain non-terminal while safe useful work exists. `DISCOVERY_REFRESH_REQUIRED` and `RELEASE_READY` remain review/orchestration outcomes rather than Execution Agent self-declarations.

## Fail-closed transitions

A transition is rejected when project, preparation, Definition, execution/revision, root/branch/commit or authority binding does not match canonical state.

Future workstream dispatch additionally fails closed on mismatched workstream identity, scope ownership, shared-contract versions, dependency readiness or required resource lease.
