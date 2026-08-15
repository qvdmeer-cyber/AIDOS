# AIDOS repository agent instructions

This repository is the single source of truth for the **generic AIDOS method, agents, protocols, bridge contracts, reusable tools/validators and generalized learning**.

## Hard boundaries

- Do not add organisation-documentation procedures to AIDOS.
- Do not copy project strategy, product requirements, architecture, runtime truth, customer context or secrets into AIDOS.
- Project-specific truth belongs in the project repository.
- Generic AIDOS agents are defined once here. Projects configure them; projects do not fork or duplicate them.
- Reusable learning must be generalized before entering AIDOS and must retain provenance/evidence.
- A generic heuristic may never silently override project truth, an accepted documentation baseline or a human-accepted Definition.
- Prefer one canonical source per project truth-domain. AIDOS manifests point to project truth; they do not duplicate it.

## Agent hierarchy

Use the generic agents in `agents/`:

1. Project Documentation Agent — establishes/maintains trustworthy project-local canonical sources using repository inventory plus one-question-at-a-time human gap resolution.
2. Definition Agent — defines one development goal and obtains human acceptance.
3. Worker Agent — bounded planning, dispatch, review and state control.
4. Execution Agent — technical execution only.

The Project Documentation Agent and Definition Agent are conversational/human-facing when decisions are needed, but their durable truth lives in project-repository state rather than chat history.

## Knowledge selection

Load context in this order:

```text
AIDOS core
→ relevant capability knowledge
→ relevant goal-pattern knowledge
→ project profile + accepted project documentation sources
→ accepted Definition
→ current Execution
```

Do not load unrelated accumulated knowledge merely because it exists.

## Durable state

A chat/session is disposable. Essential state must be reconstructable from project-repository state and append-only events.

Project documentation builder progress belongs under project-local `.aidos/documentation/` state; the actual canonical documentation remains at the project's chosen source paths.

## Changes to AIDOS itself

Prefer this learning ladder:

```text
observed project fact
→ candidate generalized lesson
→ evidence/provenance review
→ proven knowledge
→ reusable validator/tool/skill where possible
→ protocol simplification when structurally justified
```

Executable prevention is preferred over longer prose when the same failure class can be machine-detected.
