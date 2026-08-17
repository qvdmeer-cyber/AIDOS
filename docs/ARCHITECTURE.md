# AIDOS architecture

## Purpose

AIDOS is the private orchestration, governance and learning layer around existing AI runtimes. There is conceptually **one Artificial Intelligence Development Operating System** managing multiple isolated development projects.

```text
AIDOS
├─ Project A
├─ Project B
└─ Project C
```

A project is an isolated development instance managed by AIDOS; it does not have its own independent AIDOS. GPT/Codex sessions are temporary actors and are never project state or source of truth.

```text
AIDOS-Contracts
  → shared Baseline / Decision Governance / Discovery Closure interfaces

AIDOS-Builder
  → Evidence Inventory / Project Baseline / Existing Project Discovery

Project repository
  → accepted project truth + evidence + decisions + durable project/workstream state

AIDOS Core/Runtime
  → portfolio/project/workstream orchestration, Definition, Auto Define, execution, review, controls, learning
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
→ material product/runtime/content graph CLOSED
→ Accepted Current Product State
→ Definition
```

Lifecycle ordering/promotion semantics may be versioned separately. Auto Define and workstream/control-plane changes do not silently change that lifecycle.

For an existing product, the primary repository is the discovery root, not the assumed system boundary. Current closure-compatible preparation uses CPS/discovery catalog/state 0.3.0.

## Authority architecture

Several authority dimensions remain distinct:

- `PROJECT_ACCESS.json` — project/source boundaries;
- `DISCOVERY_AUTHORITY.json` — read/runtime evidence collection;
- Decision Governance — who/what may resolve an unresolved Baseline/Definition concern;
- Execution envelopes — mutation/deployment authority for one bounded accepted goal.

No access or authority is transitive across sibling projects/workstreams. Confidence never expands an authority boundary.

## Decision authority / Auto Define

AIDOS-Contracts defines the shared decision taxonomy:

```text
SYSTEM_INVARIANT
REPO_VERIFIABLE
AUTO_DECIDABLE
HUMAN_REQUIRED
```

These classes answer a different question from source/execution authority: **how may this unresolved project concern be resolved?**

### Resolution paths

```text
SYSTEM_INVARIANT
→ higher-authority AIDOS contract/governance source
→ SYSTEM_DEFINED

REPO_VERIFIABLE
→ authorized project-local canonical evidence
→ REPO_VERIFIED

AUTO_DECIDABLE
→ Decision Assessment
→ policy-valid AUTO_DECISION
→ otherwise HUMAN_REQUIRED

HUMAN_REQUIRED
→ durable Human Input Request
→ human decision
```

`SYSTEM_INVARIANT` and `REPO_VERIFIABLE` are not AI project preferences. Only `AUTO_DECIDABLE` produces an autonomous project choice.

### Auto Decision gate

A Decision Assessment records confidence, reversibility, authority, material alternatives, impact dimensions and missing evidence.

Current shared policy permits autonomy only when:

- inside existing authority;
- no materially equivalent competing alternative remains;
- all product/business, security/privacy, destructive, external-cost/commitment, compatibility and blast-radius impacts are at most `LOW`;
- missing evidence is at most `LOW`;
- confidence is `HIGH`, or confidence is `MEDIUM` and the choice is fully `REVERSIBLE`.

`LOW`, irreversible, outside-authority or materially impactful/evidence-deficient decisions become human gates.

The real material decision space is preserved; AIDOS must not create artificial A/B options.

### Durable decision state

Definition Auto Decisions live under:

```text
.aidos/definitions/<definition_id>/v<version>/decisions/<decision_id>.json
```

They bind exact Definition version/target, choice, alternatives, rationale, assessment, provenance, actor/model/session and supersession lineage.

Human, Auto, system and repository resolutions remain distinguishable in durable state and Definition progress.

A new evidence state or human override supersedes/reopens rather than rewriting prior decision history.

### Fixed-point convergence

A Definition Thinker does not simply consume a question queue:

```text
accepted preparation + desired intent
→ applicability/progress
→ Auto Define fixed-point pass
   ├─ system resolutions
   ├─ repository resolutions
   ├─ policy-valid Auto Decisions
   └─ Human Input Request only when genuinely required
→ human response
→ fresh Auto Define pass over all remaining concerns
→ Definition readiness validation
→ explicit human Definition acceptance
```

Auto Define therefore reduces human questions without removing the final human Definition gate.

Project Baseline uses the same shared Decision Governance policy through AIDOS-Builder; Core does not duplicate Baseline completeness.

See `docs/AUTO_DEFINE.md`.

## One project, multiple workstreams

An accepted Definition may be decomposed into multiple parallel workstreams when dependencies make this safe and useful.

```text
Project
├─ project-level reasoning
├─ Workstream A → Thinker → Worker
├─ Workstream B → Thinker → Worker
└─ Workstream C → Thinker → Worker
```

Parallelization is optional. AIDOS chooses sequential versus parallel execution from scope ownership, shared contracts, dependency graph, blockers, shared-resource lease requirements and integration risk/gates.

Each workstream has durable identity/state under `schemas/workstream.schema.json`. See `docs/WORKSTREAM_ORCHESTRATION.md`.

## Actor-role abstraction

Mature orchestration distinguishes roles from concrete model/chat identities:

- `THINKER` — bounded reasoning/planning/review;
- `WORKER` — bounded technical execution/mutation;
- `HUMAN` — genuine product/risk/authority decisions.

`DEFINITION_AGENT` and reasoning/review `WORKER_AGENT` can serve Thinker roles; `EXECUTION_AGENT`/Codex serves the technical Worker role. Existing persisted identities are not renamed merely to match the abstraction.

## AIDOS owns control flow

```text
AIDOS
→ select next valid actor from durable state
→ activate actor with exact project/workstream/bindings
→ actor produces durable event/result/request
→ AIDOS validates/reconciles
→ AIDOS selects next valid actor
```

An actor may propose an Auto Decision, dispatch, repair, escalation or human input, but the runtime applies only transitions/resolutions that pass canonical state, policy, authority and lease validation.

This keeps workflow continuity independent of any one GPT/Codex session.

## Durable events and projections

Project/workstream state combines append-only events/evidence with compact current projections for routing/status. Session summaries are never a replacement for durable state.

Decision records, Human Input Requests and their bindings are part of this durable control plane.

## Concurrency, leases and integration

The existing execution lease prevents duplicate execution of one project/revision and remains valid runtime semantics.

Parallel workstreams additionally require shared-resource claims/leases for conflicting resources. General workstream resource leasing remains runtime integration work.

A workstream may complete locally but remain `WAITING_INTEGRATION`. Combined acceptance requires applicable shared-contract, build/test, migration/data, runtime, Definition and release gates.

See `docs/CONCURRENCY_AND_RECOVERY.md`.

## Human Input Requests

Human input is first-class durable state, not a property of a GPT chat.

```text
actor/Auto Define reaches genuine human boundary
→ Human Input Request WAITING
→ authorized channel presents it
→ response persisted/validated
→ request RESOLVED
→ AIDOS chooses next actor
```

For Auto Define escalation, a request may carry authority classification, Decision Assessment reference and explicit stop reason. Options represent the actual material choice space.

The currently proven top-level runtime still uses `WAITING_USER`; the Human Input Request provides the exact durable reason/binding behind that projection.

See `protocols/INTERRUPTION_PROTOCOL.md`.

## Definition readiness validation

Definition completion is not inferred from conversation confidence.

`Test-AidosDefinitionReady.ps1` composes:

- `Test-AidosDefinitionProgress.ps1 -RequireReady`;
- resolved Definition Applicability when present;
- `Test-AidosDefinitionDecisions.ps1` for exact decision binding, current Auto Decision policy validity and supersession lineage.

This gate proves structural/decision-policy readiness; explicit human Definition acceptance remains separate.

## Control plane

AIDOS must be controllable independently of a UI through explicit control intents: run/start, pause, resume, safe stop, status query, Human Input response and recovery request.

> **An interface passes intent; AIDOS remains authority and decides how the intent is safely executed.**

No client/UI may directly start/kill Codex, rewrite project state or mutate project files outside AIDOS orchestration.

General remote control runtime implementation remains roadmap work. See `docs/CONTROL_PLANE.md`.

## Progress and ETA

AIDOS may expose probabilistic project/workstream progress and Estimated Time Remaining from Definition scope, workstreams, dependency graph, weighted remaining work and validation/integration status.

ETA carries explicit confidence. Progress/ETA are operational projections only; Definition + evidence + validation/integration/release gates determine actual completeness.

See `docs/PROGRESS_AND_ESTIMATION.md`.

## Observability, portfolio insights and learning

AIDOS observes project/workstream execution, repair/revision cycles, blockers/recovery, Human Input Requests, first-pass acceptance, waits, phase durations, Definition gaps and estimation error.

Auto Define adds decision telemetry: authority distribution, confidence/reversibility, autonomous decisions, later supersession/revision, human overrides and escalation reasons. `schemas/auto-define-evaluation.schema.json` defines a durable per-Definition aggregate.

Learning remains:

```text
OBSERVATION
→ HYPOTHESIS / learning candidate
→ explicit review/adoption
→ ADOPTED_IMPROVEMENT
```

A statistical pattern never directly becomes a system rule or expands autonomous authority.

A key maturity metric is **what human attention is still needed for**, and whether it shifts from operational/technical intervention toward genuine product, risk and strategic decisions.

## External Interface boundary

A future external **AIDOS Interface** is a separate layer/project above Core.

```text
AIDOS Core / Runtime
├─ project/workstream state
├─ decision/explainability state
├─ controls
├─ Human Input Requests
├─ events/metrics/estimates/insights
└─ explicit API/event boundary
        ↓
future AIDOS Interface
```

AIDOS must function fully without the Interface. The Interface observes/submits intent; it owns no essential orchestration or Auto Define policy logic.

No Interface UI or separate Interface project is implemented here.

## Definition and execution lifecycle

Once preparation is valid:

```text
accepted preparation
→ Definition applicability + progress
→ Auto Define fixed point
→ Human Input only where required
→ deterministic Definition readiness
→ explicit human Definition acceptance
→ project/workstream planning
→ bounded executions
→ validation/review
→ integration gates where parallelized
→ release governance where applicable
```

For existing projects, Definition remains the desired delta from accepted closure-compatible CPS.

## Fail-closed runtime binding

Execution continues to bind exact project/preparation/Definition/execution identities. Workstream-enabled execution additionally binds workstream/scope/shared contracts/resources once runtime-supported.

Decision resolution also fails closed when decision authority, assessment, evidence, Definition version or supersession state does not match canonical durable state.

## Recovery

Power loss, process crash or session rotation is recovered from durable project/workstream state, decisions, events, Git bindings, leases, review transport and Human Input Requests. A session may disappear without deleting workflow state.

## Separation of truth

- **AIDOS-Contracts** — generic versioned preparation and Decision Governance contracts.
- **AIDOS-Builder** — distributable Baseline/Discovery procedures and validators.
- **AIDOS Core** — private orchestration/control/Definition Auto Define/execution/review/learning capability.
- **Project repositories** — project-specific accepted truth, evidence, decisions and durable workflow state.

Principle: **Project-local truth; AIDOS-global capability and control flow.**
