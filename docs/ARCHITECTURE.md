# AIDOS architecture

## Purpose

AIDOS is an orchestration and governance layer around existing AI runtimes. It is not an LLM platform and does not attempt to replace ChatGPT or Codex.

The first target runtime is:

- normal ChatGPT chats for high-value definition/reasoning/review;
- Codex using `gpt-5.4-mini` with `medium` reasoning as the default execution worker;
- Git/project repositories as durable state and evidence transport;
- a local Windows bridge for project routing, session lifecycle, concurrency and event-driven handoff.

Model/runtime choices are configuration, not architectural identity.

## Components

```text
Human
  │
  ▼
Definition Agent (ChatGPT)
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

## Separation of truth

### AIDOS repository

Contains generic capability:

- agents;
- protocols;
- schemas/contracts;
- bridge/tooling;
- reusable validators;
- generalized knowledge;
- templates.

### Project repository

Contains project truth:

- business/product sources;
- architecture/runtime/deployment sources;
- project-specific `AGENTS.md`;
- AIDOS project profile;
- Definitions and acceptance;
- executions and event history;
- project-specific validators and evidence.

Principle: **Project-local truth; AIDOS-global capability.**

## Definition-first lifecycle

Development cannot start from an unreviewed agent-generated plan.

```text
source inventory
→ unknown/ambiguous decisions
→ one-question-at-a-time elicitation
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

## Event sourcing

Project state has two representations:

1. **append-only event log** — durable history of what occurred;
2. **current state projection** — compact current status used for routing.

State can be rebuilt from events. Chat history is not required for recovery.

## Isolation

A project execution binds at minimum:

```text
project_id
repo
official_root
branch
accepted_definition_id/version
execution_id/revision
codex_session_id
commit_sha / expected head where relevant
review_id where relevant
```

A mismatch fails closed.

## Multi-project operation

AIDOS may manage many active projects concurrently. Workflow concurrency is distinct from local heavy-job concurrency.

The bridge schedules local work based on resource policy while each project retains independent state, Codex session and review lifecycle.

## Human control

The human remains required for:

- acceptance of a new/reopened Definition;
- new product choices;
- material authority expansion;
- destructive/non-reversible operations outside pre-authorized scope;
- unresolved contradictions/blockers.

The bridge must support a supervised mode where locking the Windows session prevents the next interactive GPT cycle while allowing an already-running bounded Codex execution to finish safely.
