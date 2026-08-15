# AIDOS

**Artificial Intelligence Development Operating System**

AIDOS is a human-governed operating model for AI-assisted software development. It separates product definition, high-value reasoning, technical execution, review, recovery and reusable learning so that AI agents can work autonomously inside explicit boundaries without making product decisions on behalf of the human owner.

The name also echoes Ancient Greek *aidōs*: respect, self-restraint and awareness of proper boundaries — a useful description of the intended operating model.

## Core idea

```text
Human
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

AIDOS is designed around five rules:

1. **Definition before execution.** Development starts only after the human explicitly accepts the foreseeable product behaviour, constraints and acceptance criteria.
2. **Project-local truth.** Product, architecture, runtime and project-specific instructions stay in the project repository. AIDOS does not become a central project-knowledge dump.
3. **AIDOS-global capability.** Generic agents, protocols, tools, validators and proven reusable learnings live once in AIDOS.
4. **Goal-scoped context.** Agents receive AIDOS knowledge selected for the current development goal instead of the entire accumulated knowledge base.
5. **Bounded autonomy.** An execution agent may work for as long as useful inside the accepted goal and authority, but must stop at product contradictions, material authority boundaries or terminal completion.

## Repository responsibility

AIDOS owns:

- generic agent definitions;
- definition/execution/review/escalation/recovery protocols;
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
- accepted project definitions and execution history;
- customer/project secrets or credentials.

Those remain in the relevant project repository.

## Agent model

AIDOS defines three primary generic agents:

- **Definition Agent** — discovers missing decisions one question at a time and produces a human-accepted Definition.
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
Project profile and project truth
  ↓
Accepted Definition
  ↓
Current Execution
```

More specific accepted/project truth wins over generic heuristics. AIDOS learning may improve future execution, but may never silently override project truth or a human-accepted Definition.

## Durable state

Chats and Codex sessions are disposable reasoning contexts. They are never the only source of essential state.

Each integrated project stores its own AIDOS state in the project repository, including accepted definitions, executions, current state and an append-only event history. This allows Conversation/Worker/Codex sessions to be rotated or recovered without reconstructing truth from old chat history.

## Status

AIDOS is being built from a proven manual GPT ↔ Codex workflow. The first implementation target is a Windows-based multi-project bridge using normal ChatGPT chats for reasoning and Codex with a lightweight execution model for implementation.

Initial design documentation and machine-readable contracts live in this repository. The existing Workflow V2 remains separate as a fallback and is not modified by AIDOS.
