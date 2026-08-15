# AIDOS repository agent instructions

This repository is the single source of truth for the **generic AIDOS method, agents, protocols, bridge contracts, reusable tools/validators and generalized learning**.

## Hard boundaries

- Do not add organisation-documentation procedures to AIDOS.
- Do not copy project strategy, product requirements, architecture, runtime truth, customer context or secrets into AIDOS.
- Project-specific truth belongs in the project repository.
- Generic AIDOS agents are defined once here. Projects configure them; projects do not fork or duplicate them.
- Reusable learning must be generalized before entering AIDOS and must retain provenance/evidence.
- A generic heuristic may never silently override project truth or a human-accepted Definition.

## Agent hierarchy

Use the generic agents in `agents/`:

1. Definition Agent — requirements discovery and human acceptance.
2. Worker Agent — bounded planning, dispatch, review and state control.
3. Execution Agent — technical execution only.

## Knowledge selection

Load context in this order:

```text
AIDOS core
→ relevant capability knowledge
→ relevant goal-pattern knowledge
→ project profile/truth
→ accepted Definition
→ current Execution
```

Do not load unrelated accumulated knowledge merely because it exists.

## Durable state

A chat/session is disposable. Essential state must be reconstructable from project-repository state and append-only events.

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
