# AIDOS repository agent instructions

This repository is the single source of truth for the **private AIDOS runtime method, Definition/Worker/Execution agents, orchestration, reusable execution tools/validators and generalized learning**.

## Ecosystem boundaries

- Project-baseline completeness contracts belong in `qvdmeer-cyber/AIDOS-Contracts`.
- The distributable Project Documentation Agent/Builder belongs in `qvdmeer-cyber/AIDOS-Builder`.
- Project/customer truth belongs in the project repository.
- Organisation-context repositories may be referenced by a project under explicit access contracts, but their content is not copied into AIDOS.

## Hard boundaries

- Do not add organisation-documentation procedures to AIDOS.
- Do not reintroduce the Project Documentation Builder or baseline catalog here.
- Do not copy project strategy, product requirements, architecture, runtime truth, customer context or secrets into AIDOS.
- Generic private AIDOS runtime agents are defined once here; projects configure them rather than forking them.
- Reusable learning must be generalized before entering AIDOS and must retain provenance/evidence.
- A generic heuristic may never silently override an accepted project baseline, project truth or a human-accepted Definition.

## Agent hierarchy

Use the private runtime agents in `agents/`:

1. Definition Agent — defines one development goal and obtains human acceptance.
2. Worker Agent — bounded planning, dispatch, review and state control.
3. Execution Agent — technical execution only.

Project preparation happens before this hierarchy through AIDOS-Builder and AIDOS-Contracts.

## Knowledge selection

Load context in this order:

```text
AIDOS core
→ relevant capability knowledge
→ relevant goal-pattern knowledge
→ accepted project baseline + project truth
→ accepted Definition
→ current Execution
```

Do not load unrelated accumulated knowledge merely because it exists.

## Durable state

A chat/session is disposable. Essential state must be reconstructable from project-repository state and append-only events.

The accepted baseline remains project-local under the AIDOS-Contracts format. AIDOS consumes it; it does not own or regenerate it.

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
