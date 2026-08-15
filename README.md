# AIDOS

**Artificial Intelligence Development Operating System**

AIDOS is the private core for human-governed AI software development. It separates human-accepted goal definition, high-value reasoning, technical execution, review, recovery and reusable learning so that AI agents can work autonomously inside explicit boundaries without making product decisions on behalf of the human owner.

The name also echoes Ancient Greek *aidōs*: respect, self-restraint and awareness of proper boundaries.

## Ecosystem boundary

AIDOS is intentionally separated from project preparation:

```text
AIDOS-Contracts
  → shared project-baseline/access contracts

AIDOS-Builder
  → distributable project documentation/completeness builder

Project repository
  → project truth + accepted baseline + decisions

AIDOS (this repository)
  → private definition/orchestration/execution/review/learning core
```

The private AIDOS core does not need to be shared with a collaborator who only uses AIDOS-Builder.

## Core flow

```text
Accepted Project Baseline
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

## Core rules

1. **Accepted project truth before goal definition.** A project enters AIDOS with a baseline prepared under AIDOS-Contracts, normally by AIDOS-Builder.
2. **Definition before execution.** Development starts only after the human explicitly accepts the foreseeable product behaviour, constraints and acceptance criteria for the goal.
3. **Project-local truth.** Product, architecture, runtime and project-specific instructions stay in the project repository.
4. **AIDOS-global capability.** Generic runtime agents, protocols, tools, validators and proven reusable learnings live once in AIDOS.
5. **Goal-scoped context.** Agents receive AIDOS knowledge selected for the current development goal rather than the whole accumulated knowledge base.
6. **Bounded autonomy.** Execution may continue as long as useful inside accepted goal/authority, but stops at contradictions, material authority boundaries or terminal completion.

## Repository responsibility

AIDOS owns:

- Definition, Worker and Execution agent definitions;
- definition/execution/review/escalation/recovery protocols;
- bridge/orchestration implementation;
- session rotation and multi-project execution rules;
- reusable validators, tools and skills;
- goal/capability-scoped learned knowledge;
- telemetry and learning logic;
- private runtime/project integration.

AIDOS does **not** own:

- the distributable Project Documentation Builder;
- the generic project-baseline completeness contract;
- organisation-documentation procedures;
- project strategy/product requirements/architecture/runtime truth;
- accepted project baselines, definitions or execution history;
- customer/project secrets or credentials.

See:

- `qvdmeer-cyber/AIDOS-Builder`
- `qvdmeer-cyber/AIDOS-Contracts`

## Agent model

AIDOS defines three private runtime agents:

- **Definition Agent** — discovers missing goal decisions one question at a time and produces a human-accepted Definition.
- **Worker Agent** — plans bounded execution from an accepted Definition, dispatches work, reviews evidence and controls state transitions.
- **Execution Agent** — performs technical execution, tests, deployment/verification where authorized, repairs ordinary failures and returns terminal outcomes.

Project documentation preparation is handled outside this private core by AIDOS-Builder.

## Knowledge inheritance

```text
AIDOS Core
  ↓
relevant capability knowledge
  ↓
relevant goal-pattern knowledge
  ↓
accepted project baseline + project truth
  ↓
accepted goal Definition
  ↓
current Execution
```

More specific accepted/project truth wins over generic heuristics. AIDOS learning may improve future execution but may never silently override project truth or a human-accepted Definition.

## Durable state

Chats and Codex sessions are disposable reasoning contexts. Essential state must be reconstructable from repository state and append-only events.

The project baseline remains in the project repository under the AIDOS-Contracts format. AIDOS adds goal definitions, executions, reviews and runtime state to that same project-local boundary.

## Current implementation status

The private AIDOS foundation is present. The local multi-project bridge, Codex lifecycle, review transport, desktop ChatGPT integration and crash reconciliation remain the main runtime implementation work.

Projects must first have an accepted AIDOS Project Baseline. `tools/New-AidosProject.ps1` now refuses initialization when `.aidos/documentation/PROJECT_BASELINE.json` is absent.

The existing Workflow V2 remains separate as a fallback and is not modified by AIDOS.
