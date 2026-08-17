# AIDOS architecture

## Purpose

AIDOS is the private orchestration, governance and learning layer around existing AI runtimes. There is conceptually **one Artificial Intelligence Development Operating System** managing multiple isolated development projects.

```text
AIDOS
├─ Project A
├─ Project B
└─ Project C
```

A project is an isolated development instance managed by AIDOS; it does not have its own independent AIDOS. GPT/Codex sessions are temporary actors inside those instances and are never project state or source of truth.

Project preparation remains deliberately separated from private Definition/Execution orchestration:

```text
AIDOS-Contracts
  → deterministic Project Baseline + Discovery Closure interfaces

AIDOS-Builder
  → Evidence Inventory / Project Baseline / Current Product State implementation

Project repository
  → accepted project truth + evidence + durable project/workstream state

AIDOS Core/Runtime
  → portfolio/project/workstream orchestration, Definition, execution, review, controls, learning
```

## Preparation architecture

The current preparation lifecycle remains:

```text
NEW_PROJECT
Accepted Project Baseline
→ Definition

EXISTING_PROJECT
Accepted Project Baseline
→ Existing Project Discovery
→ material product graph CLOSED
→ Accepted Current Product State
→ Definition
```

Lifecycle ordering/promotion semantics may be versioned separately; the workstream/control-plane architecture in this document does not silently change that existing preparation contract.

For an existing product, the primary repository is the discovery root, not the assumed system boundary. AIDOS-Builder recursively follows `FIRST_PARTY_MATERIAL` dependencies and reasonably observable runtime until deterministic Discovery Closure passes.

## Authority architecture

Project/source authority, Discovery Authority and Execution Authority remain separate.

- `PROJECT_ACCESS.json` describes project/source boundaries.
- `DISCOVERY_AUTHORITY.json` governs read/runtime evidence collection.
- AIDOS Execution envelopes govern mutation/deployment authority for a bounded accepted goal.

No access/authority is transitive across sibling projects or workstreams.

## One project, multiple workstreams

An accepted Definition may be decomposed into multiple parallel workstreams when dependencies make this safe and useful.

```text
Project
├─ project-level reasoning
├─ Workstream A → Thinker → Worker
├─ Workstream B → Thinker → Worker
└─ Workstream C → Thinker → Worker
```

Parallelization is optional. AIDOS chooses sequential versus parallel execution from:

- workstream scope ownership;
- shared contracts;
- dependency graph;
- blockers;
- shared-resource lease requirements;
- integration risk/gates.

Each workstream has durable identity/state under `schemas/workstream.schema.json`. See `docs/WORKSTREAM_ORCHESTRATION.md`.

## Actor-role abstraction

Mature orchestration distinguishes actor roles from concrete model/chat identities:

- `THINKER` — bounded reasoning/planning/review;
- `WORKER` — bounded technical execution/mutation;
- `HUMAN` — genuine product/risk/authority decisions.

To preserve current proven runtime terminology, `DEFINITION_AGENT` and the existing reasoning/review `WORKER_AGENT` can serve Thinker roles, while `EXECUTION_AGENT`/Codex serves the Worker role. Existing reviewer identity/contracts are not renamed by this abstraction.

## AIDOS owns control flow

Thinkers and Workers do not directly own each other's lifecycle.

Canonical orchestration is:

```text
AIDOS
→ select next valid actor from durable state
→ activate actor with exact project/workstream/bindings
→ actor produces durable event/result/request
→ AIDOS validates/reconciles
→ AIDOS selects next valid actor
```

An actor may request dispatch, repair, escalation or human input, but the AIDOS runtime/Bridge applies the transition only after validating canonical state, authority and leases.

This keeps workflow continuity independent of any single GPT/Codex session.

## Durable events and projections

Project/workstream state has two forms:

1. durable append-only events/evidence;
2. compact current projections for routing/status.

`event.schema.json` supports optional `workstream_id`, Human Input Request/control bindings and abstract actor roles while preserving existing concrete actor identities.

Session summaries are never a replacement for durable state.

## Concurrency, leases and integration

The existing execution lease prevents duplicate execution of one project/revision and remains valid runtime semantics.

Parallel workstreams additionally require shared-resource claims/leases for conflicting resources. General workstream resource leasing is an architectural requirement, not yet a proven runtime capability.

A workstream may complete locally but remain `WAITING_INTEGRATION`. The combined result is accepted only after applicable integration gates pass: shared-contract compatibility, combined build/tests, migrations/data compatibility, runtime validation and Definition/release convergence.

See `docs/CONCURRENCY_AND_RECOVERY.md`.

## Human Input Requests

Human input is a first-class durable object, not a property of a Conversation/GPT chat.

`schemas/human-input-request.schema.json` binds one concrete question/decision to project/workstream and relevant Definition/execution/revision/review state.

```text
actor reaches genuine human boundary
→ Human Input Request WAITING
→ any authorized channel presents it
→ response persisted/validated
→ request RESOLVED
→ AIDOS chooses next actor
```

The currently proven top-level runtime still uses `WAITING_USER`; the Human Input Request provides the durable reason/binding behind that state without prematurely renaming existing runtime state semantics.

See `protocols/INTERRUPTION_PROTOCOL.md`.

## Control plane

AIDOS must be controllable independently of a UI through explicit control intents:

- run/start;
- pause;
- resume;
- safe stop;
- status query;
- Human Input response;
- recovery request.

`schemas/control-intent.schema.json` defines the core envelope.

Core rule:

> **An interface passes intent; AIDOS remains authority and decides how the intent is safely executed.**

No client/UI may directly start/kill Codex, rewrite project state or mutate project files outside AIDOS orchestration.

General remote control runtime implementation is roadmap work. Existing supervised-session behaviour already demonstrates part of the safe-boundary model: an already-running bounded execution may finish while the next interactive actor remains blocked.

See `docs/CONTROL_PLANE.md`.

## Progress and ETA

AIDOS may expose probabilistic project/workstream progress and Estimated Time Remaining using `schemas/progress-estimate.schema.json`.

Progress is not simple task-count completion. Where possible it derives from Definition scope, workstreams, dependency graph, weighted remaining work and validation/integration status.

ETA carries explicit confidence (`HIGH`, `MEDIUM`, `LOW`, `NOT_RELIABLY_ESTIMABLE`). Estimated versus actual remaining time should be preserved to improve calibration.

Progress/ETA are operational projections only. Definition + evidence + validation/integration/release gates determine actual completeness.

See `docs/PROGRESS_AND_ESTIMATION.md`.

## Observability, portfolio insights and learning

AIDOS observes project/workstream execution, repair/revision cycles, blockers/recovery, Human Input Requests, first-pass acceptance, wait categories, phase durations, Definition gaps and estimation error.

Portfolio-level aggregation may analyze autonomy/reliability trends and recurring bottlenecks while preserving project isolation.

Learning uses a strict maturity distinction:

```text
OBSERVATION
→ HYPOTHESIS / learning candidate
→ explicit review/adoption
→ ADOPTED_IMPROVEMENT
```

A statistical pattern never directly becomes a system rule. `schemas/system-insight.schema.json` and `protocols/LEARNING_PROTOCOL.md` make this durable.

A key maturity metric is **what human attention is still needed for**, and whether that attention shifts from operational/technical intervention toward genuine product, risk and strategic decisions.

## External Interface boundary

A future external **AIDOS Interface** is a separate layer/project above Core.

```text
AIDOS Core / Runtime
├─ project/workstream state
├─ controls
├─ Human Input Requests
├─ events/metrics/estimates/insights
└─ explicit API/event boundary
        ↓
future AIDOS Interface
```

AIDOS must function fully without the Interface. The Interface observes and submits intent through explicit contracts; it owns no essential orchestration logic.

No Interface UI or separate Interface project is implemented in AIDOS Core here.

## Definition and execution lifecycle

Once preparation is valid:

```text
accepted preparation
→ Definition applicability + durable progress
→ human-accepted Definition
→ project/workstream planning
→ bounded executions
→ validation/review
→ integration gates where parallelized
→ release governance where applicable
```

For existing projects, Definition remains a desired delta from the accepted closure-compatible CPS.

## Fail-closed runtime binding

Execution continues to bind exact project/preparation/Definition/execution identities. Workstream-enabled execution additionally requires exact workstream/scope/shared-contract/resource bindings once runtime support is implemented.

A mismatch is a control-flow failure, not something an actor may guess through.

## Recovery

Power loss, process crash or session rotation is recovered from durable project/workstream state, events, Git bindings, leases, review transport and Human Input Requests. A session may disappear without deleting workflow state.

## Separation of truth

- **AIDOS-Contracts** owns generic versioned preparation contracts.
- **AIDOS-Builder** owns distributable preparation procedures/validators.
- **AIDOS Core** owns private orchestration/control/agents/learning contracts.
- **Project repositories** own project-specific accepted truth and durable project/workstream state.

Principle: **Project-local truth; AIDOS-global capability and control flow.**
