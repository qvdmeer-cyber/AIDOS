# AIDOS architecture

## Purpose

AIDOS is the private orchestration, governance and learning layer around existing AI runtimes. It is not an LLM platform and does not attempt to replace ChatGPT or Codex.

Project preparation is deliberately separated:

```text
AIDOS-Contracts
  → deterministic Project Baseline + Existing Project Discovery interfaces

AIDOS-Builder
  → distributable evidence inventory / baseline / Current Product State implementation

Project repository
  → accepted project truth + evidence + current-state snapshot

AIDOS
  → private goal definition, orchestration, execution, review and learning
```

The first target runtime is:

- normal ChatGPT chats for high-value definition/reasoning/review;
- Codex using `gpt-5.4-mini` with `medium` reasoning as the default execution worker;
- Git/project repositories as durable state and evidence transport;
- a local Windows bridge for project routing, session lifecycle, concurrency and event-driven handoff.

Model/runtime choices are configuration, not architectural identity.

## Preparation model

The first source/code inventory is shared across project preparation rather than repeated by separate phases.

```text
commit-bound Evidence Inventory
        │
        ├─ Project Baseline mapping
        │
        └─ Existing Project Discovery enrichment
```

Then project mode determines the gate:

```text
NEW_PROJECT
Accepted Project Baseline
→ Definition

EXISTING_PROJECT
Accepted Project Baseline
→ deterministic Existing Project Discovery
→ Accepted Current Product State
→ Definition
```

The Current Product State (CPS) reconstructs current capabilities/flows and explicitly separates implementation evidence from observed runtime evidence.

## Runtime components

```text
Accepted preparation state
  │
  ▼
Human + Definition Agent (ChatGPT)
  │ defines desired delta
  ▼
Accepted Definition ───────────────┐
  │                                │ contradiction
  ▼                                │
Worker Agent (ChatGPT)             │
  │                                │
  ▼                                │
Execution Envelope                 │
  │                                │
  ▼                                │
Local Bridge                       │
  │ selects project/root/session   │
  ▼                                │
Execution Agent / Codex            │
  │                                │
  ▼                                │
Evidence + terminal handoff        │
  │                                │
  ▼                                │
Worker review ─────────────────────┘
```

For product/material releases, a release-scoped governance layer is established before the final development phase wherever practical:

```text
Human + Definition Agent
  ↓
Accepted Launch Definition
  ↓
RELEASE_SCOPE_FROZEN
  ↓
final bounded goals/executions
  ↓
Worker release-gate review
  ↓
RELEASE_READY
  ↓
release lifecycle / real users
```

## Separation of truth

### AIDOS-Contracts

Contains shared stable interfaces needed across repositories, including:

- Project Baseline catalog/schema;
- repository-access model;
- Evidence Inventory schema;
- Existing Project Discovery surface catalog;
- Current Product State schema.

It contains no project truth or private orchestration logic.

### AIDOS-Builder

Contains distributable project preparation:

- Project Documentation/Baseline Agent;
- shared repository/evidence inventory tooling;
- Existing Project Discovery Agent/procedure;
- deterministic baseline/CPS validators;
- explicit acceptance tooling.

It writes only to project-local state and allowed context is read-only/bounded.

### AIDOS repository

Contains private runtime capability:

- Definition/Worker/Execution agents;
- runtime protocols and state contracts;
- bridge/orchestration tooling;
- reusable execution validators;
- generalized goal/capability knowledge;
- learning/session/recovery logic.

### Project repository

Contains project truth:

- accepted AIDOS Project Baseline;
- shared commit-bound Evidence Inventory;
- accepted Current Product State for existing products;
- project/product sources;
- architecture/runtime/deployment sources;
- project-specific `AGENTS.md`;
- AIDOS project profile;
- Definitions and acceptance;
- Launch Definition/release-governance state where applicable;
- executions and event history;
- post-launch backlog;
- project-specific validators and evidence.

Explicit additional context repositories may inform baseline/discovery/Definition only when declared under the project-access contract. Their access is non-transitive and normally read-only.

Principle: **Project-local truth; AIDOS-global capability.**

## Existing Project Discovery invariant

For `EXISTING_PROJECT`, Definition must not be used as an informal reverse-engineering phase.

AIDOS-Builder reconstructs current state first across bounded discovery surfaces: source/modules, routes/entrypoints, UI/admin, background work, data/schema, auth/permissions, interfaces, integrations, configuration/flags, runtime/deployment, tests and documentation claims.

Required distinction:

```text
implementation state
!=
observed runtime state
```

Code presence cannot silently become `OBSERVED_WORKING`. Source/runtime/data/config/documentation disagreement becomes explicit `CONFLICT`/`DRIFT`.

Deterministic coverage proves all required discovery surfaces were handled and every inventoried item was mapped/classified. Human acceptance then freezes the CPS snapshot used by Definition.

Definition asks only about the desired **delta** from that accepted current state.

## Definition-first lifecycle

Development cannot start from an unreviewed agent-generated plan.

```text
accepted preparation state
→ goal-specific unknown/ambiguous decisions
→ one-question-at-a-time Definition elicitation
→ proposed Definition
→ human review
→ ACCEPTED
→ consistency check against baseline/current state
→ execution planning
→ plan-vs-Definition check
→ execution
→ convergence review against Definition
```

If implementation evidence later shows CPS was stale/wrong, refresh Existing Project Discovery rather than silently rewriting current-state history through Definition.

## Launch discipline

AIDOS must prevent a second failure mode as well: execution can be perfectly bounded while the human continuously moves the release finish line.

For a product/material release, define an explicit **Launch Definition / Release Gate before the final development phase wherever practical**.

Architectural invariant:

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

After Launch Definition acceptance:

- release scope is frozen;
- new findings are classified as `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`;
- useful non-blocking improvements are preserved in a post-launch backlog;
- subjective polish or a new feature idea cannot silently extend the release;
- when all accepted launch criteria PASS, the default state is `RELEASE_READY`;
- delaying after `RELEASE_READY` requires explicit Launch Definition/release-scope reopen with reason and consequence recorded;
- after launch, optimization should increasingly use evidence from real users/operations rather than speculative pre-launch refinement.

See `protocols/LAUNCH_PROTOCOL.md`.

## Event sourcing

AIDOS runtime project state has two representations:

1. **append-only event log** — durable history of what occurred;
2. **current state projection** — compact current status used for routing.

State can be rebuilt from events. Chat history is not required for recovery.

## Isolation

A project execution binds at minimum:

```text
project_id
project_mode
repo
official_root
branch
accepted_baseline version/commit
accepted_current_product_state id/commit (EXISTING_PROJECT)
accepted_definition_id/version
execution_id/revision
codex_session_id
commit_sha / expected head where relevant
review_id where relevant
```

Release-scoped executions additionally bind the accepted Launch Definition/release identity when that runtime contract is implemented.

A mismatch fails closed.

Repository access is explicit per project. A context repository or sibling project is not reachable merely because the machine owner has access to it.

## Multi-project operation

AIDOS may manage many active projects concurrently. Workflow concurrency is distinct from local heavy-job concurrency.

The bridge schedules local work based on resource policy while each project retains independent credentials/access, preparation/current-state bindings, state, Codex session and review lifecycle.

## Human control

The human remains required for:

- acceptance of Project Baseline and Current Product State during external preparation;
- acceptance of a new/reopened Definition;
- acceptance/reopening of a Launch Definition;
- new product choices;
- material authority expansion;
- destructive/non-reversible operations outside pre-authorized scope;
- unresolved contradictions/blockers;
- deliberate release delay after `RELEASE_READY`.

The human is not asked to manually rediscover objective current-product facts when evidence can establish them.

The bridge must support a supervised mode where locking the Windows session prevents the next interactive GPT cycle while allowing an already-running bounded Codex execution to finish safely.
