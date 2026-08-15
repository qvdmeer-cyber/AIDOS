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
- A generic heuristic may never silently override an accepted project baseline, project truth, human-accepted Definition or frozen Launch Definition.
- Once an accepted Launch Definition is satisfied, do not treat further improvement, subjective incompleteness or a newly imagined feature as sufficient grounds to delay release.
- Delaying after `RELEASE_READY` requires an explicit Launch Definition/release-scope reopen with reason/consequence recorded.

## Agent hierarchy

Use the private runtime agents in `agents/`:

1. Definition Agent — defines one development goal, obtains human acceptance and establishes/reopens a Launch Definition where applicable.
2. Worker Agent — bounded planning, dispatch, review, release-scope discipline and state control.
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
→ accepted Launch Definition where applicable
→ current Execution
```

Do not load unrelated accumulated knowledge merely because it exists.

## Launch governance

For product/material releases, use `protocols/LAUNCH_PROTOCOL.md`.

Invariant:

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

After release-scope freeze, classify new material findings only as:

- `LAUNCH_BLOCKER`;
- `POST_LAUNCH`;
- `EVIDENCE_REQUIRED`.

Preserve valuable non-blocking ideas in the project-local post-launch backlog rather than silently expanding the release.

## Durable state

A chat/session is disposable. Essential state must be reconstructable from project-repository state and append-only events.

The accepted baseline remains project-local under the AIDOS-Contracts format. AIDOS consumes it; it does not own or regenerate it.

Launch Definition, release-scope and post-launch backlog state are likewise project-local when their runtime contracts are implemented.

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
