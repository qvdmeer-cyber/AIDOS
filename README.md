# AIDOS

**Artificial Intelligence Development Operating System**

AIDOS is a human-governed operating model for AI-assisted software development. It separates project documentation, product definition, high-value reasoning, technical execution, review, recovery and reusable learning so that AI agents can work autonomously inside explicit boundaries without making product decisions on behalf of the human owner.

The name also echoes Ancient Greek *aidōs*: respect, self-restraint and awareness of proper boundaries — a useful description of the intended operating model.

## Core idea

```text
Human
  ↓
Project Documentation Agent
  ↓
TRUSTWORTHY PROJECT-LOCAL SOURCES
  ↓
Definition Agent
  ↓
ACCEPTED DEFINITION
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

AIDOS is designed around six rules:

1. **Project truth before goal definition.** Agents first establish which project-local sources are trustworthy instead of rediscovering the project from chat history.
2. **Definition before execution.** Development starts only after the human explicitly accepts the foreseeable product behaviour, constraints and acceptance criteria.
3. **Project-local truth.** Product, architecture, runtime and project-specific instructions stay in the project repository. AIDOS does not become a central project-knowledge dump.
4. **AIDOS-global capability.** Generic agents, protocols, tools, validators and proven reusable learnings live once in AIDOS.
5. **Goal-scoped context.** Agents receive AIDOS knowledge selected for the current development goal instead of the entire accumulated knowledge base.
6. **Bounded autonomy.** An execution agent may work for as long as useful inside the accepted goal and authority, but must stop at product contradictions, material authority boundaries or terminal completion.

## Repository responsibility

AIDOS owns:

- generic agent definitions;
- project-documentation/definition/execution/review/escalation/recovery protocols;
- bridge state and event contracts;
- session-rotation rules;
- reusable validators, tools and skills;
- goal/capability-scoped learned knowledge;
- telemetry contracts;
- project integration templates.

AIDOS does **not** own:

- organisation-documentation procedures;
- project strategy or product requirements;
- project architecture/runtime truth;
- project-specific agent instructions;
- accepted project documentation, definitions and execution history;
- customer/project secrets or credentials.

Those remain in the relevant project repository.

## Agent model

AIDOS defines four primary generic agents:

- **Project Documentation Agent** — inventories existing project sources, resolves material documentation gaps one question at a time and maintains the project-local canonical-source map without creating duplicate truth.
- **Definition Agent** — discovers missing decisions one question at a time and produces a human-accepted Definition for one development goal.
- **Worker Agent** — plans bounded execution from an accepted Definition, dispatches work, reviews evidence and controls state transitions.
- **Execution Agent** — performs implementation, tests, deployment/verification where authorized, repairs ordinary technical failures and returns only terminal outcomes.

Projects configure these agents; they do not fork or duplicate them.

## Knowledge inheritance

```text
AIDOS Core
  ↓
Capability knowledge
  ↓
Goal-pattern knowledge
  ↓
Project profile + accepted project documentation sources
  ↓
Accepted Definition
  ↓
Current Execution
```

More specific accepted/project truth wins over generic heuristics. AIDOS learning may improve future execution, but may never silently override project truth or a human-accepted Definition.

## Project documentation single source of truth

AIDOS does not require projects to copy their documentation into an AIDOS-specific documentation tree.

Instead, each project may keep a small `.aidos/documentation/MANIFEST.json` that identifies the canonical source for material concerns such as architecture, runtime, deployment and security. Existing reliable project docs remain canonical. Missing focused docs are created only where needed.

The interactive entrypoint is `START_PROJECT_DOCUMENTATION.md`.

## Durable state

Chats and Codex sessions are disposable reasoning contexts. They are never the only source of essential state.

Each integrated project stores its own AIDOS state in the project repository, including documentation baseline/session state, accepted definitions, executions, current state and an append-only event history. This allows Documentation/Definition/Worker/Codex sessions to be rotated or recovered without reconstructing truth from old chat history.

## Repository map

- `agents/` — generic AIDOS agents.
- `protocols/` — project documentation, definition, execution, review, interruption and learning protocols.
- `schemas/` — machine-readable project/documentation/state/event/Definition/execution/learning contracts.
- `knowledge/` — generic reusable knowledge, selected by capability/goal.
- `bridge/` — local Windows orchestration layer and bridge module.
- `tools/` — project/bootstrap/documentation validation and future maintenance tooling.
- `templates/` — project-local integration templates.
- `docs/` — architecture, project documentation, security, state, recovery, telemetry and implementation roadmap.

## Current implementation status

The initial AIDOS foundation is present, including generic agents/protocols, machine-readable contracts, project bootstrap, state-transition primitives and implementation roadmap.

The Project Documentation Builder can already be used independently of the future unattended bridge through `START_PROJECT_DOCUMENTATION.md`. It has persistent project-local manifest/session contracts plus PowerShell bootstrap/validation tooling.

The bridge is **not yet an unattended production runner**. Codex CLI lifecycle, leases/scheduler, ephemeral review-ref automation, desktop ChatGPT triggering and crash reconciliation remain the next runtime implementation tranche. See `docs/IMPLEMENTATION_ROADMAP.md`.

AIDOS is being built from a proven manual GPT ↔ Codex workflow. The existing Workflow V2 remains separate as a fallback and is not modified by AIDOS.
