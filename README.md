# AIDOS

**Artificial Intelligence Development Operating System**

AIDOS is the private orchestration, governance and learning layer around AI development runtimes. It is not one project and it is not one GPT/Codex chat.

## One AIDOS, multiple isolated projects

There is conceptually one AIDOS runtime managing multiple development instances:

```text
AIDOS
├─ Project A
├─ Project B
└─ Project C
```

Each project owns its own durable truth, authority and workflow state. GPT/Codex sessions are temporary actors inside a project and can be replaced without losing workflow state.

Core principle:

> **Project-local truth; AIDOS-global capability and control flow.**

## Ecosystem boundary

```text
AIDOS-Contracts
  → Project Baseline + Discovery Closure contracts

AIDOS-Builder
  → distributable preparation / Existing Project Discovery

Project repository
  → accepted project truth + evidence + durable project/workstream state

AIDOS Core/Runtime
  → Definition, orchestration, controls, execution/review, recovery, learning
```

A future external **AIDOS Interface** is a separate client layer/project above Core. No Interface UI is implemented here.

## Current preparation gate

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

For existing products, the primary repository is only the discovery root. Material first-party components and reasonably observable runtime must be closed under the current Discovery Closure rules.

This profile/workstream/control expansion does not silently change the current preparation lifecycle ordering; that remains a separately versioned governance decision.

## Core runtime flow

The mature control abstraction is:

```text
AIDOS
→ select next actor from durable state
→ activate exact actor/project/workstream binding
→ actor emits durable result/event/request
→ AIDOS validates/reconciles
→ AIDOS selects next valid actor
```

Actors do not directly own one another's lifecycle.

### Actor roles

- **Thinker** — bounded reasoning/planning/review.
- **Worker** — bounded technical execution/mutation.
- **Human** — genuine product/risk/authority decisions.

Existing concrete identities are preserved: `DEFINITION_AGENT` and the current reasoning/review `WORKER_AGENT` can serve Thinker roles; `EXECUTION_AGENT`/Codex serves the technical Worker role.

## Multiple workstreams inside one project

An accepted Definition may be executed sequentially or decomposed into parallel workstreams, for example API, frontend, admin and integration/tests.

A workstream has durable:

- identity and Definition binding;
- scope ownership;
- shared contracts;
- dependency graph;
- blockers;
- shared-resource claims/leases;
- integration gates.

Parallelization is optional and dependency-driven. AIDOS must not parallelize when shared state/uncertainty makes that unsafe.

A local workstream result is not automatically an integrated project result. Applicable cross-workstream integration gates must pass first.

See `docs/WORKSTREAM_ORCHESTRATION.md` and `schemas/workstream.schema.json`.

## Control plane

AIDOS must be controllable without depending on a UI. External clients submit intent; Core remains authority.

Core control intents include:

```text
RUN
PAUSE
RESUME
SAFE_STOP
QUERY_STATUS
SUBMIT_HUMAN_INPUT
REQUEST_RECOVERY
```

> **The interface passes intent. AIDOS decides how that intent can safely be applied.**

No UI/client may directly start/kill Codex, rewrite state or mutate project files outside AIDOS orchestration.

General remote-control execution is roadmap work. Existing supervised-session behaviour already proves part of the safe-boundary semantics.

See `docs/CONTROL_PLANE.md` and `schemas/control-intent.schema.json`.

## Human Input Requests

Human input is a first-class durable object, not a property of a GPT chat.

```text
actor reaches genuine human boundary
→ Human Input Request WAITING
→ any authorized channel can present it
→ human response is validated/persisted
→ request RESOLVED
→ AIDOS chooses next actor
```

Requests bind the exact project/workstream and relevant Definition/execution/revision/review state. The current top-level runtime state `WAITING_USER` remains valid; the request supplies the durable reason/question behind it.

See `schemas/human-input-request.schema.json` and `protocols/INTERRUPTION_PROTOCOL.md`.

## Composable project profiles

AIDOS reuses versioned profile layers to shorten project/Definition reasoning:

```text
PRODUCT_ARCHETYPE
CAPABILITY
INTEGRATION
STACK
INFRASTRUCTURE
EXPOSURE_RISK
```

Examples of Product Archetypes include web/mobile/desktop applications, API/background services, CLI/library/browser extension, CMS, ChatGPT app and MCP server.

Profiles are hypotheses/accelerators, never project truth. Verified project evidence and explicit accepted decisions override them.

Project Applicability answers which development surfaces exist/may exist. Definition Applicability answers which of those are affected by one desired delta.

See `docs/PROFILE_PRESETS.md`.

## Definition progress

Definition state is durable and per-surface. A new/rotated GPT session resumes from project-local applicability/progress rather than chat memory.

After every human Definition decision:

```text
persist decision
→ update applicability/progress
→ validate
→ show current surface progress
→ ask next question
```

## Progress and ETA

AIDOS may expose probabilistic project/workstream progress and Estimated Time Remaining.

Progress is not simple task-count completion. Where possible it uses Definition scope, workstreams, dependency graph, weighted remaining work, validation and integration status.

ETA carries explicit confidence (`HIGH`, `MEDIUM`, `LOW`, `NOT_RELIABLY_ESTIMABLE`). Estimated versus actual remaining time can be retained to calibrate future estimates.

Progress/ETA are estimates only. Definition + evidence + validation/integration/release gates determine actual completeness.

See `docs/PROGRESS_AND_ESTIMATION.md`.

## Observability and learning

AIDOS records project/workstream executions/revisions, repair cycles, blockers/recoveries, Human Input reasons, first-pass acceptance, wait categories, phase durations, Definition gaps exposed during execution and estimation error.

Portfolio-level analysis may track autonomy/reliability and recurring bottlenecks while preserving project isolation.

Learning distinguishes:

```text
OBSERVATION
→ HYPOTHESIS / learning candidate
→ explicit review/adoption
→ ADOPTED_IMPROVEMENT
```

A statistical pattern never automatically becomes a system rule.

A key maturity metric is **where human attention is still required** and whether it shifts from operational/technical problems toward genuine product, risk and strategic decisions.

See `docs/TELEMETRY.md`, `protocols/LEARNING_PROTOCOL.md` and `schemas/system-insight.schema.json`.

## Launch governance

For product/material releases, accepted Launch Definition freezes release criteria. New findings become `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`. When accepted criteria pass, the default state is `RELEASE_READY`; improvement alone is not sufficient grounds for delay.

## Durable state and recovery

Chats and Codex sessions are disposable. Essential state is reconstructable from project/workstream objects, append-only events, Git bindings, leases, review transport, Human Input Requests and canonical project sources.

Crash/restart/session replacement must never require hidden chat memory to recover control flow.

## Implementation status

Already present/proven foundations include exact project/execution binding, execution leases, bounded Codex lifecycle, deterministic validation, review transport/cleanup, fail-closed recovery and supervised interactive-session gating.

New **architecture/contracts now present** include workstreams, actor-role/control-flow model, Human Input Requests, control intents, progress/ETA and Observation/Hypothesis/Adopted-Improvement insight contracts.

Their full multi-workstream/control-plane runtime implementation remains roadmap work. See `docs/CORE_ORCHESTRATION_ROADMAP.md`.

The external AIDOS Interface UI is explicitly not part of this Core implementation.
