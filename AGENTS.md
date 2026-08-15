# AIDOS repository agent instructions

This repository is the single source of truth for the **private AIDOS runtime method, Definition/Worker/Execution agents, orchestration, reusable execution tools/validators and generalized learning**.

## Ecosystem boundaries

- Project Baseline + Existing Project Discovery/Current Product State contracts belong in `qvdmeer-cyber/AIDOS-Contracts`.
- The distributable Project Documentation + Existing Project Discovery procedures belong in `qvdmeer-cyber/AIDOS-Builder`.
- Project/customer truth, shared evidence and accepted current-product snapshots belong in the project repository.
- Organisation-context repositories may be referenced by a project under explicit access contracts, but their content is not copied into AIDOS.

## Hard boundaries

- Do not add organisation-documentation procedures to AIDOS.
- Do not reintroduce Project Documentation/Existing Project Discovery implementation or completeness catalogs here.
- Do not copy project strategy, product requirements, architecture, runtime truth, customer context or secrets into AIDOS.
- For `EXISTING_PROJECT`, do not begin Definition without an accepted compatible Current Product State.
- Do not use Definition/Worker review as an informal substitute for Existing Project Discovery; if the CPS is materially stale/wrong, transition to `DISCOVERY_REFRESH_REQUIRED` and route to AIDOS-Builder.
- Generic private AIDOS runtime agents are defined once here; projects configure them rather than forking them.
- Reusable learning must be generalized before entering AIDOS and must retain provenance/evidence.
- A generic heuristic may never silently override an accepted Project Baseline, Current Product State, project truth, human-accepted Definition or frozen Launch Definition.
- Once an accepted Launch Definition is satisfied, do not treat further improvement, subjective incompleteness or a newly imagined feature as sufficient grounds to delay release.
- Delaying after `RELEASE_READY` requires an explicit Launch Definition/release-scope reopen with reason/consequence recorded.

## Agent hierarchy

Use the private runtime agents in `agents/`:

1. Definition Agent — consumes accepted preparation state, defines one desired delta/goal, obtains human acceptance and establishes/reopens a Launch Definition where applicable.
2. Worker Agent — bounded planning, dispatch, review, release-scope discipline and state control.
3. Execution Agent — technical execution only.

Project preparation happens before this hierarchy through AIDOS-Builder and AIDOS-Contracts.

## Preparation inheritance

```text
NEW_PROJECT
accepted Project Baseline
→ Definition

EXISTING_PROJECT
accepted Project Baseline
→ accepted Current Product State
→ Definition
```

The shared project-local Evidence Inventory may support both baseline and Current Product State but is not itself permission to infer runtime functionality.

## Knowledge selection

Load context in this order:

```text
AIDOS core
→ relevant capability knowledge
→ relevant goal-pattern knowledge
→ accepted Project Baseline
→ accepted Current Product State (EXISTING_PROJECT)
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

Accepted Project Baseline, shared Evidence Inventory and Current Product State remain project-local under AIDOS-Contracts/Builder formats. AIDOS consumes them; it does not own or regenerate them.

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
