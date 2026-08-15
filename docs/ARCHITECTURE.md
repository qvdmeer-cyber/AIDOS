# AIDOS architecture

## Purpose

AIDOS is the private orchestration, governance and learning layer around existing AI runtimes. It is not an LLM platform and does not attempt to replace ChatGPT or Codex.

Project preparation is deliberately separated:

```text
AIDOS-Contracts
  → deterministic Project Baseline/access interfaces

AIDOS-Builder
  → distributable inventory/interview/completeness implementation

Project repository
  → accepted project truth

AIDOS
  → private goal definition, orchestration, execution, review and learning
```

The first target runtime is:

- normal ChatGPT chats for high-value definition/reasoning/review;
- Codex using `gpt-5.4-mini` with `medium` reasoning as the default execution worker;
- Git/project repositories as durable state and evidence transport;
- a local Windows bridge for project routing, session lifecycle, concurrency and event-driven handoff.

Model/runtime choices are configuration, not architectural identity.

## Components

```text
Accepted Project Baseline
  │
  ▼
Human + Definition Agent (ChatGPT)
  │
  ▼
Accepted Definition ───────────────┐
  │                                │
  ▼                                │ contradiction
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

Contains shared stable interfaces needed across repositories, including the Project Baseline and explicit repository-access model. It contains no project truth or private orchestration logic.

### AIDOS-Builder

Contains the distributable Project Documentation Agent and deterministic preparation tooling. It consumes AIDOS-Contracts and writes only to the project repository.

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
- project/product sources;
- architecture/runtime/deployment sources;
- project-specific `AGENTS.md`;
- AIDOS project profile;
- Definitions and acceptance;
- Launch Definition/release-governance state where applicable;
- executions and event history;
- post-launch backlog;
- project-specific validators and evidence.

Explicit additional context repositories may inform the baseline/Definition only when declared under the project-access contract. Their access is non-transitive and normally read-only.

Principle: **Project-local truth; AIDOS-global capability.**

## Baseline-first, Definition-first lifecycle

Development cannot start from an unreviewed agent-generated plan.

```text
fixed Project Baseline catalog
→ repository/context inventory
→ deterministic completeness
→ human acceptance of durable project baseline
→ goal-specific unknown/ambiguous decisions
→ one-question-at-a-time Definition elicitation
→ proposed Definition
→ human review
→ ACCEPTED
→ consistency check
→ execution planning
→ plan-vs-Definition check
→ execution
→ convergence review against Definition
```

A material contradiction discovered during implementation reopens the Definition rather than allowing Worker/Codex to invent product behaviour.

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

Launch Definition acceptance, release-scope freeze, release-finding classification, `RELEASE_READY` and explicit reopen should become first-class durable events when runtime persistence contracts are implemented.

## Isolation

A project execution binds at minimum:

```text
project_id
repo
official_root
branch
accepted_baseline version/commit
accepted_definition_id/version
execution_id/revision
codex_session_id
commit_sha / expected head where relevant
review_id where relevant
```

Release-scoped executions will additionally bind the accepted Launch Definition/release identity when that runtime contract is implemented.

A mismatch fails closed.

Repository access is explicit per project. A context repository or sibling project is not reachable merely because the machine owner has access to it.

## Multi-project operation

AIDOS may manage many active projects concurrently. Workflow concurrency is distinct from local heavy-job concurrency.

The bridge schedules local work based on resource policy while each project retains independent credentials/access, state, Codex session and review lifecycle.

## Human control

The human remains required for:

- acceptance of a new/reopened Definition;
- acceptance/reopening of a Launch Definition;
- new product choices;
- material authority expansion;
- destructive/non-reversible operations outside pre-authorized scope;
- unresolved contradictions/blockers;
- deliberate release delay after `RELEASE_READY`.

The human is **not** routinely re-asked for additional improvements once frozen launch criteria are satisfied.

The bridge must support a supervised mode where locking the Windows session prevents the next interactive GPT cycle while allowing an already-running bounded Codex execution to finish safely.
