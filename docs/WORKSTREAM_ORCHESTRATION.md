# Workstream orchestration

## One AIDOS, many isolated projects

There is conceptually one **Artificial Intelligence Development Operating System (AIDOS)**. AIDOS owns portfolio-level orchestration and manages many isolated project instances.

```text
AIDOS
├─ Project A
├─ Project B
└─ Project C
```

A project is not its own AIDOS. GPT/Codex chats and sessions are temporary actors inside a project and never the source of truth.

Project truth and workflow state remain durable in the project repository; portfolio/runtime coordination belongs to the AIDOS runtime.

## Parallel workstreams inside one project

An accepted Definition may be decomposed into multiple workstreams when dependencies and shared-resource ownership make parallel execution safe and useful.

```text
Project
├─ project-level reasoning
├─ Workstream A · API
├─ Workstream B · frontend
├─ Workstream C · admin
└─ Workstream D · integration/tests
```

Parallelization is an AIDOS decision, not a default. Sequential execution remains valid when shared state, architectural uncertainty or integration risk makes concurrency counterproductive.

Each workstream has durable identity and state using `schemas/workstream.schema.json` and should be stored under a project-local path such as:

```text
.aidos/workstreams/<workstream_id>/WORKSTREAM.json
```

## Workstream invariants

Every workstream must define:

- stable `workstream_id` and project/Definition binding;
- explicit scope ownership;
- shared contract references;
- dependency edges to other workstreams;
- blockers;
- shared-resource claims;
- integration gate references;
- current execution/actor state where applicable.

### Scope ownership

A workstream may own paths, development surfaces and output artifacts. Ownership is not permission to ignore shared contracts. A workstream may not silently change another workstream's owned surface or shared interface.

Cross-workstream changes require one of:

1. an already-accepted shared-contract change path;
2. AIDOS re-planning/rebinding affected workstreams;
3. escalation to a Thinker/Human when the change alters accepted product intent or authority.

### Shared contracts

Parallel workstreams coordinate through explicit shared contracts rather than informal chat assumptions. Examples include API schemas, shared domain types, database migrations, routing contracts and integration test contracts.

A workstream may depend on a contract without owning it. Contract changes must be version/binding aware and must invalidate or revalidate dependent workstreams deterministically.

### Dependency graph

Dependencies are explicit and typed:

- `HARD` — downstream work cannot safely proceed until satisfied;
- `SOFT` — work may proceed with bounded assumptions, but integration remains blocked;
- `INTEGRATION` — individual work may complete, but project acceptance requires combined validation.

AIDOS uses the graph to decide whether workstreams may execute in parallel.

## Actor roles versus current concrete agent names

The mature orchestration abstraction uses actor roles:

```text
THINKER
WORKER
HUMAN
```

- **Thinker** performs bounded reasoning/planning/review for a project or workstream.
- **Worker** performs bounded technical execution/mutation.
- **Human** resolves genuine product/risk/authority decisions.

For backward compatibility with the proven runtime terminology:

- the current `DEFINITION_AGENT` and reasoning/review `WORKER_AGENT` can serve the **THINKER** role;
- the current `EXECUTION_AGENT` / Codex serves the **WORKER** role.

This role abstraction does **not** rename the current persisted reviewer identity or review contracts. It sits above them and allows future temporary Thinker/Worker sessions per workstream without breaking existing runtime semantics.

## AIDOS owns control flow

Actors do not directly own the next actor.

Canonical flow:

```text
AIDOS
→ activate actor with exact binding
→ actor produces durable state/event/result
→ AIDOS validates/reconciles
→ AIDOS chooses next valid actor
```

A Thinker can request dispatch and a Worker can publish terminal evidence, but neither directly starts or resumes the other. The Bridge/runtime is responsible for validating state, bindings, leases and authority before activation.

This ensures a replacement GPT/Codex session can resume from durable state without inheriting hidden control flow from a predecessor chat.

## Resource and execution leases

The existing project execution lease remains valid and proven semantics for preventing duplicate execution of one revision.

Parallel workstreams add a second conceptual resource-lease layer for conflicting shared resources, for example:

- exclusive write ownership of a schema/migration surface;
- exclusive runtime/deployment environment;
- shared database or package-generation resource;
- integration branch/ref or other merge-sensitive output.

`resource_claims` declare whether a resource is shared-read, exclusive-write or exclusive-runtime. AIDOS must acquire the required lease before dispatching a conflicting Worker.

**Current implementation status:** project/revision execution leases exist. General workstream/shared-resource leases are architecture requirements and are not yet runtime-proven.

## Integration gates

A workstream can be technically complete without the project result being integrated.

Parallel work is accepted as an integrated result only after applicable integration gates pass, including where relevant:

- shared contract compatibility;
- merge/build consistency;
- cross-workstream tests;
- migrations/data compatibility;
- representative runtime validation;
- Definition convergence across the combined result;
- release gate checks where applicable.

A workstream may therefore reach `WAITING_INTEGRATION` before `INTEGRATED`.

## Recovery

Crash/restart recovery reconstructs workstream state from project-local objects, events, leases, Git state and active process/session evidence. A temporary Thinker/Worker session is replaceable; workstream identity and bindings are not.
