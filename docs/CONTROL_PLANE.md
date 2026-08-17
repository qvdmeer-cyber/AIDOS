# AIDOS control plane

## Purpose

AIDOS must be operable independently of any specific UI. External tools, future interfaces and supervised operators submit **control intent**; the AIDOS runtime remains the authority that decides whether and how that intent can safely be applied.

> **The interface transmits intent. AIDOS owns orchestration, authority checks, state transitions and actor activation.**

An interface must never directly start/kill Codex, mutate project files, rewrite state projections or bypass AIDOS bindings/leases.

## Control capabilities

Core control intents include `RUN`, `PAUSE`, `RESUME`, `SAFE_STOP`, `QUERY_STATUS`, `SUBMIT_HUMAN_INPUT` and `REQUEST_RECOVERY`.

The control envelope is `schemas/control-intent.schema.json`.

A request is not itself a state transition:

```text
RECEIVED
→ validate identity / authority / current state
→ ACCEPTED or REJECTED
→ apply through AIDOS runtime
→ APPLIED or FAILED
```

## Safe-boundary semantics

`PAUSE` stops new actor/work activation after the next safe boundary. An already-running bounded execution may finish/publish terminal evidence when abrupt termination is less safe.

`RESUME` reloads canonical project/workstream state and validates blockers/leases/recovery before activating the next actor.

`SAFE_STOP` converges toward no new work and no unsafe in-flight mutation. It is not equivalent to killing a process tree.

**Current implementation status:** supervised-session behaviour already blocks the next interactive GPT activation while permitting an already-running bounded Codex execution to finish. General remote pause/resume/safe-stop remains runtime roadmap work.

## Human Input Requests

Human input is durable AIDOS state, not a GPT-chat property. `schemas/human-input-request.schema.json` binds the exact project/workstream and relevant Definition/execution/revision/review.

Recommended location:

```text
.aidos/human-input/<request_id>.json
```

```text
actor reaches human boundary
→ request WAITING
→ response arrives through authorized channel
→ AIDOS validates binding/response
→ request RESOLVED + event
→ AIDOS chooses next actor
```

## Status/query capability

Read-only status output uses `schemas/runtime-status.schema.json` and can expose portfolio projects, workstreams, blockers/recovery, open Human Input Requests, current actor roles and progress-estimate references.

Status visibility never grants mutation authority.

## Future external Interface boundary

The concrete **AIDOS Interface** is outside AIDOS Core implementation.

```text
AIDOS Core / Runtime
├─ project + workstream state
├─ orchestration/control plane
├─ Human Input Requests
├─ events/metrics/estimates/insights
└─ explicit interface contracts/API/events
        ↓
future AIDOS Interface project
```

A future Interface may provide dashboards, progress/ETA, human decisions and controls. It remains replaceable: AIDOS must function when the Interface is offline or absent.

No Interface UI or separate Interface project is implemented here.
