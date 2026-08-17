# AIDOS

**Artificial Intelligence Development Operating System**

AIDOS is the private orchestration, governance and learning layer around AI development runtimes. It is not one project and it is not one GPT/Codex chat.

## One AIDOS, multiple isolated projects

```text
AIDOS
├─ Project A
├─ Project B
└─ Project C
```

Each project owns its own durable truth, authority and workflow state. GPT/Codex sessions are temporary actors and can be replaced without losing workflow state.

> **Project-local truth; AIDOS-global capability and control flow.**

## Ecosystem boundary

```text
AIDOS-Contracts
  → shared Baseline / Decision Governance / Discovery Closure contracts

AIDOS-Builder
  → distributable Project Baseline + Existing Project Discovery

Project repository
  → accepted truth + evidence + decisions + durable project/workstream state

AIDOS Core/Runtime
  → Definition, Auto Define, orchestration, controls, execution/review, recovery, learning
```

A future external **AIDOS Interface** is a separate client layer/project. No Interface UI is implemented in Core.

## Current preparation gate

```text
NEW_PROJECT
Accepted Project Baseline
→ Definition

EXISTING_PROJECT
Accepted Project Baseline
→ Existing Project Discovery
→ material product/runtime/content graph CLOSED
→ Accepted Current Product State
→ Definition
```

For existing products, current compatible Discovery Closure uses CPS/discovery catalog/state 0.3.0. The primary repository is only the discovery root.

This work does not change the current preparation lifecycle ordering; lifecycle reordering remains a separately versioned governance decision.

## Core runtime flow

```text
AIDOS
→ select next actor from durable state
→ activate exact actor/project/workstream binding
→ actor emits durable result/event/request
→ AIDOS validates/reconciles
→ AIDOS selects next valid actor
```

Actors do not directly own one another's lifecycle.

Abstract roles are **Thinker**, technical **Worker** and **Human**. Existing concrete identities remain compatible: `DEFINITION_AGENT` and reasoning/review `WORKER_AGENT` can serve Thinker roles; `EXECUTION_AGENT`/Codex serves the technical Worker role.

## Auto Define — confidence-driven autonomous Definition

Before AIDOS asks the human about an unresolved Definition concern, it classifies decision authority through shared AIDOS-Contracts Decision Governance:

```text
SYSTEM_INVARIANT
REPO_VERIFIABLE
AUTO_DECIDABLE
HUMAN_REQUIRED
```

Resolution model:

```text
SYSTEM_INVARIANT
→ resolve from AIDOS governance/contracts

REPO_VERIFIABLE
→ resolve from authorized project-local canonical evidence

AUTO_DECIDABLE
→ Decision Assessment
→ persist AUTO_DECISION only when policy permits
→ otherwise HUMAN_REQUIRED

HUMAN_REQUIRED
→ durable Human Input Request
```

Only `AUTO_DECIDABLE` is an autonomous project choice. System invariants and repository facts are direct higher-authority/evidence resolutions rather than hidden model decisions.

### Confidence is not authority

Current policy permits an Auto Decision only when it is inside authority, no materially equivalent alternative remains, material impacts/evidence gaps are at most `LOW`, and either:

- confidence is `HIGH`; or
- confidence is `MEDIUM` and the decision is fully `REVERSIBLE`.

`LOW` confidence, irreversibility, material product/business/security/privacy/destructive/external-cost/compatibility/blast-radius impact, material missing evidence or uncertain/out-of-bounds authority requires human input.

Do not manufacture A/B choices. The option set reflects the actual material decision space.

### Durable Definition decisions

Auto Decisions live at:

```text
.aidos/definitions/<definition_id>/v<version>/decisions/<decision_id>.json
```

They contain exact binding, chosen value, alternatives, rationale, Decision Assessment, evidence/source refs, actor/model/session attribution and supersession lineage. Human and Auto Decisions remain distinguishable.

Tools:

```text
tools/New-AidosDefinitionAutoDecision.ps1
tools/Test-AidosAutoDecision.ps1
tools/Test-AidosDefinitionDecisions.ps1
tools/Test-AidosDefinitionReady.ps1
```

### Fixed-point Definition convergence

At Definition start/resume, after every human response, after material new evidence and after decision supersession:

```text
repeat
  resolve SYSTEM_INVARIANT
  resolve REPO_VERIFIABLE
  persist policy-valid AUTO_DECIDABLE choices
  update applicability/progress
until no more concerns can close safely

if HUMAN_REQUIRED remains
  publish one Human Input Request
else
  proceed to Definition review
```

A human answer therefore does not automatically lead to the next precomputed question; AIDOS first tries to close all remaining safely inferable decisions.

Auto Define optimizes **convergence**, not final authority. The complete Definition still requires explicit human acceptance before execution.

See `docs/AUTO_DEFINE.md` and `protocols/DEFINITION_PROTOCOL.md`.

## Project Baseline Auto Define

AIDOS-Builder uses the same shared authority/confidence policy for Project Baseline preparation. New authority-aware Baselines use contract 0.2.0; legacy accepted Baseline 0.1 remains preserved lineage.

Core does not duplicate Builder Baseline completeness logic.

## Multiple workstreams inside one project

An accepted Definition may remain sequential or be decomposed into parallel workstreams such as API, frontend, admin and integration/tests.

A workstream has durable identity, scope ownership, shared contracts, dependencies, blockers, shared-resource claims/leases and integration gates. Parallelization is optional and dependency-driven.

A local workstream result is not automatically an integrated project result. Applicable integration gates must pass.

See `docs/WORKSTREAM_ORCHESTRATION.md` and `schemas/workstream.schema.json`.

## Control plane

AIDOS is controllable independently of a UI. External clients submit intent; Core remains authority.

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

No client may directly start/kill Codex, rewrite state or mutate project files outside AIDOS orchestration.

See `docs/CONTROL_PLANE.md`.

## Human Input Requests

Human input is a first-class durable object rather than a property of a GPT chat.

```text
actor reaches genuine human boundary
→ Human Input Request WAITING
→ authorized channel presents it
→ response is validated/persisted
→ request RESOLVED
→ AIDOS selects next actor
```

For Auto Define escalation, the request may carry authority classification, Decision Assessment reference and stop reason. Its options reflect the real decision space.

See `schemas/human-input-request.schema.json` and `protocols/INTERRUPTION_PROTOCOL.md`.

## Composable project profiles and Definition applicability

AIDOS reuses versioned profile layers:

```text
PRODUCT_ARCHETYPE
CAPABILITY
INTEGRATION
STACK
INFRASTRUCTURE
EXPOSURE_RISK
```

Profiles are accelerators, never project truth. Verified project evidence and explicit accepted decisions override them.

Project Applicability answers which development surfaces exist/may exist; Definition Applicability answers which are affected by a specific delta.

See `docs/PROFILE_PRESETS.md`.

## Definition progress and readiness

Definition state is durable and per-surface. New/rotated sessions resume from project-local Definition, applicability, progress, decisions and Human Input Requests rather than chat memory.

After any resolution:

```text
persist authoritative record
→ update applicability/progress
→ validate
→ rerun Auto Define
```

After every human Definition decision, the full current surface progress is shown before another human question.

Unified readiness validation uses `Test-AidosDefinitionReady.ps1`: surface progress must be ready, applicability resolved when present, and current Auto Decision lineage/policy valid.

## Progress and ETA

AIDOS may expose probabilistic project/workstream progress and Estimated Time Remaining from Definition scope, workstreams, dependencies, weighted remaining work, validation and integration state.

ETA carries explicit confidence. Progress/ETA are estimates only; Definition + evidence + validation/integration/release gates determine actual completeness.

See `docs/PROGRESS_AND_ESTIMATION.md`.

## Observability and learning

AIDOS records execution/revision, repairs, blockers/recovery, Human Input reasons, first-pass acceptance, wait categories, Definition gaps and estimation error.

Auto Define additionally records authority classifications, Auto Decision confidence/reversibility, later revisions/supersessions, human overrides and reasons. `schemas/auto-define-evaluation.schema.json` provides a durable per-Definition aggregate shape.

Learning remains:

```text
OBSERVATION
→ HYPOTHESIS / learning candidate
→ explicit review/adoption
→ ADOPTED_IMPROVEMENT
```

Auto Define statistics never automatically expand authority or lower human-gate thresholds.

See `docs/TELEMETRY.md` and `protocols/LEARNING_PROTOCOL.md`.

## Launch governance

Accepted Launch Definition freezes release criteria. New findings become `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`. When accepted criteria pass, default state is `RELEASE_READY`; improvement alone is not sufficient grounds for delay.

## Durable state and recovery

Chats and Codex sessions are disposable. Essential state is reconstructable from project/workstream objects, decision records, events, Git bindings, leases, review transport, Human Input Requests and canonical project sources.

Crash/restart/session replacement must never require hidden chat memory to recover control flow.

## Implementation status

Already present/proven runtime foundations include exact project/execution binding, execution leases, bounded Codex lifecycle, deterministic execution validation, review transport/cleanup, fail-closed recovery and supervised interactive-session gating.

Auto Define now has shared Decision Governance contracts, durable Baseline/Definition Auto Decision writepaths, deterministic policy/lineage validators, Human Input escalation semantics, telemetry/learning semantics and regression coverage. The full runtime actor loop that automatically performs Decision Assessments and publishes/resumes Human Input Requests remains orchestration integration work.

Multi-workstream scheduling, general remote control and some portfolio aggregation also remain roadmap work. See `docs/CORE_ORCHESTRATION_ROADMAP.md`.

The external AIDOS Interface UI remains explicitly outside Core.
