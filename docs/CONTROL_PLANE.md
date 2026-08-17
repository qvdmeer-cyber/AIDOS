# AIDOS control plane

## Purpose

AIDOS must be operable independently of any specific UI. External tools, future interfaces and supervised operators submit **control intent**; the AIDOS runtime remains the authority that decides whether and how that intent can safely be applied.

> **The interface transmits intent. AIDOS owns orchestration, authority checks, state transitions and actor activation.**

An interface must never directly start/kill Codex, mutate project files, rewrite state projections or bypass AIDOS bindings/leases.

## Control capabilities

Core control intents include:

- `RUN` — start/continue eligible work;
- `PAUSE` — stop new actor activation at a safe boundary;
- `RESUME` — resume from durable state after validation;
- `SAFE_STOP` — converge to a safe stopped state;
- `QUERY_STATUS` — obtain project/workstream/runtime status;
- `SUBMIT_HUMAN_INPUT` — resolve an exact Human Input Request;
- `REQUEST_RECOVERY` — request reconciliation/recovery.

The envelope is `schemas/control-intent.schema.json`.

A control request is not itself a state transition:

```text
RECEIVED
→ validate identity / authority / current state
→ ACCEPTED or REJECTED
→ apply through AIDOS runtime
→ APPLIED or FAILED
```

## Pause, resume and safe stop

`PAUSE` means no new actor/work unit starts after the next safe boundary. A currently running bounded execution may finish and publish terminal evidence when abrupt termination is less safe.

`RESUME` reloads canonical project/workstream state, checks blockers/leases/recovery requirements and activates only the next valid actor.

`SAFE_STOP` converges toward no new work and no unsafe in-flight mutation. It is not equivalent to killing a process tree.

**Current implementation status:** supervised-session behaviour already blocks the next interactive GPT activation while permitting an already-running bounded Codex execution to finish. General remote pause/resume/safe-stop is a core requirement, not yet fully runtime-implemented.

## Human Input Requests

Human input is first-class durable AIDOS state, not a property of a GPT chat.

A request conforms to `schemas/human-input-request.schema.json` and may be stored under:

```text
.aidos/human-input/<request_id>.json
```

It binds the question to project/workstream and, where relevant, Definition/execution/revision/review. It carries concise context, one concrete decision/question, options where useful, evidence and the actor role to resume.

```text
actor reaches human boundary
→ publish Human Input Request
→ WAITING
→ response arrives through any authorized channel
→ AIDOS validates binding/response
→ RESOLVED + event
→ AIDOS chooses next actor
```

A replacement chat, mobile client or future UI can therefore resolve the same request without becoming source of truth.

## Status/query capability

Read-only status projections may expose:

- portfolio/AIDOS runtime;
- project and workstreams;
- execution/revision;
- blockers/recovery;
- Human Input Requests;
- progress/ETA estimates;
- validation/integration/release gates.

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

A future Interface may provide dashboards, progress/ETA, human decisions and controls. It must remain replaceable: AIDOS must function when that Interface is offline or absent.

No Interface UI or separate Interface project is implemented here.
