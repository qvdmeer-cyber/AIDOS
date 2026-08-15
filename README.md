# AIDOS

**Artificial Intelligence Development Operating System**

AIDOS is the private core for human-governed AI software development. It separates project preparation, human-accepted goal definition, high-value reasoning, technical execution, review, release governance, recovery and reusable learning so that AI agents can work autonomously inside explicit boundaries without making product decisions on behalf of the human owner.

The name also echoes Ancient Greek *aidōs*: respect, self-restraint and awareness of proper boundaries.

## Ecosystem boundary

AIDOS is intentionally separated from project preparation:

```text
AIDOS-Contracts
  → shared Project Baseline + Existing Project Discovery contracts

AIDOS-Builder
  → distributable baseline + Current Product State builder

Project repository
  → project truth + evidence + accepted baseline/current state + decisions

AIDOS (this repository)
  → private definition/orchestration/execution/review/learning core
```

The private AIDOS core does not need to be shared with a collaborator who only uses AIDOS-Builder.

## Preparation gate

AIDOS consumes different accepted preparation objects by project mode:

```text
NEW_PROJECT
Accepted Project Baseline
→ Definition

EXISTING_PROJECT
Accepted Project Baseline
→ Accepted Current Product State
→ Definition
```

For existing products, Current Product State reconstructs what is already implemented/observable so Definition can focus only on the desired **delta**.

## Core flow

```text
Accepted preparation state
  ↓
Definition Agent + Human
  ↓
ACCEPTED DEVELOPMENT DEFINITION
  ↓
Worker Agent
  ↓
Execution Agent / Codex
  ↓
Evidence + Review
  ↓
Worker Agent
  ├─ PASS
  ├─ REPAIR → Execution Agent
  ├─ CONTRADICTION → Definition Agent + Human
  └─ GATE/BLOCKER → Human
```

For a product/material release, AIDOS adds a release gate before the final development phase where practical:

```text
Accepted Launch Definition
  ↓
RELEASE_SCOPE_FROZEN
  ↓
final accepted work
  ↓
launch criteria PASS
  ↓
RELEASE_READY
  ↓
release / real-user evidence
```

## Core rules

1. **Accepted project truth before goal definition.** A project enters AIDOS with a compatible accepted Project Baseline; an existing product additionally requires an accepted Current Product State.
2. **Current state before change definition.** Existing functionality is discovered as evidence, not repeatedly rediscovered as product decisions inside Definition.
3. **Definition before execution.** Development starts only after the human explicitly accepts the foreseeable product behaviour, constraints and acceptance criteria for the desired change.
4. **Project-local truth.** Product, architecture, runtime, evidence, Current Product State and project-specific instructions stay in the project repository.
5. **AIDOS-global capability.** Generic runtime agents, protocols, tools, validators and proven reusable learnings live once in AIDOS.
6. **Goal-scoped context.** Agents receive AIDOS knowledge selected for the current development goal rather than the whole accumulated knowledge base.
7. **Bounded autonomy.** Execution may continue as long as useful inside accepted goal/authority, but stops at contradictions, material authority boundaries or terminal completion.
8. **Frozen launch criteria.** Launch criteria are defined before launch pressure exists. Once accepted criteria are satisfied, improvement alone is not sufficient grounds for delay; the default state is `RELEASE_READY` unless the Launch Definition is explicitly reopened.

## Repository responsibility

AIDOS owns:

- Definition, Worker and Execution agent definitions;
- definition/execution/review/launch/escalation/recovery protocols;
- bridge/orchestration implementation;
- session rotation and multi-project execution rules;
- reusable validators, tools and skills;
- goal/capability-scoped learned knowledge;
- telemetry and learning logic;
- private runtime/project integration.

AIDOS does **not** own:

- the distributable Project Documentation/Existing Project Discovery procedures;
- generic Project Baseline/Current Product State completeness contracts;
- organisation-documentation procedures;
- project strategy/product requirements/architecture/runtime truth;
- accepted Project Baselines, Current Product States, Definitions, Launch Definitions or execution history;
- customer/project secrets or credentials.

Those accepted project/release objects remain project-local.

See:

- `qvdmeer-cyber/AIDOS-Builder`
- `qvdmeer-cyber/AIDOS-Contracts`

## Agent model

AIDOS defines three private runtime agents:

- **Definition Agent** — consumes accepted current project truth, asks only goal-specific delta questions, produces a human-accepted Definition and helps establish/reopen a release-scoped Launch Definition.
- **Worker Agent** — plans bounded execution from an accepted Definition, dispatches work, reviews evidence, enforces frozen release scope and controls state transitions.
- **Execution Agent** — performs technical execution, tests, deployment/verification where authorized, repairs ordinary failures and returns terminal outcomes.

Project Baseline and Existing Project Discovery are handled outside this private core by AIDOS-Builder/AIDOS-Contracts.

## Knowledge inheritance

```text
AIDOS Core
  ↓
relevant capability knowledge
  ↓
relevant goal-pattern knowledge
  ↓
accepted Project Baseline
  ↓
accepted Current Product State (EXISTING_PROJECT only)
  ↓
accepted goal Definition
  ↓
accepted Launch Definition where applicable
  ↓
current Execution
```

More specific accepted/project truth wins over generic heuristics. AIDOS learning may improve future execution but may never silently override accepted project truth, a human-accepted Definition or a frozen Launch Definition.

## Durable state

Chats and Codex sessions are disposable reasoning contexts. Essential state must be reconstructable from repository state and append-only events.

The Project Baseline, shared Evidence Inventory and Current Product State remain in the project repository under AIDOS-Contracts/Builder formats. AIDOS adds goal definitions, Launch Definition/release state, executions, reviews and runtime state to that same project-local boundary.

## Launch governance

A release-scoped Launch Definition defines the falsifiable threshold for going to real users. After acceptance, new findings are classified as:

- `LAUNCH_BLOCKER` — objective reason the accepted release cannot safely/validly launch;
- `POST_LAUNCH` — useful improvement that must not delay launch;
- `EVIDENCE_REQUIRED` — plausible concern whose release-criticality first needs evidence.

When all frozen launch criteria PASS, Worker defaults to `RELEASE_READY` rather than asking for another round of improvements. Delaying then requires explicit scope/release-gate reopen with reason and consequence recorded.

See `protocols/LAUNCH_PROTOCOL.md`.

## Current implementation status

The private AIDOS foundation is present. The local multi-project bridge, Codex lifecycle, review transport, desktop ChatGPT integration and crash reconciliation remain the main runtime implementation work.

AIDOS onboarding now distinguishes `NEW_PROJECT` and `EXISTING_PROJECT`. Existing projects are rejected until an accepted `.aidos/discovery/CURRENT_PRODUCT_STATE.json` exists; new projects require only the accepted baseline/evidence preparation.

The existing Workflow V2 remains separate as a fallback and is not modified by AIDOS.
