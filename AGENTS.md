# AIDOS repository agent instructions

This repository is the single source of truth for the **private AIDOS runtime method, Definition/Worker/Execution agents, orchestration, reusable execution tools/validators and generalized learning**.

## Ecosystem boundaries

- Project Baseline + Discovery Closure/Current Product State contracts belong in `qvdmeer-cyber/AIDOS-Contracts`.
- Distributable Project Baseline + Existing Project Discovery procedures belong in `qvdmeer-cyber/AIDOS-Builder`.
- Project/customer truth, shared evidence, discovery authority and accepted current-product snapshots belong in the project repository.
- Organisation context may be referenced under project authority but is never copied into AIDOS core.

## Hard boundaries

- Do not add organisation-documentation procedures to AIDOS.
- Do not reimplement Project Baseline or Existing Project Discovery/completeness logic here.
- Do not copy project strategy, product requirements, architecture, runtime truth, customer context or secrets into AIDOS.
- For `EXISTING_PROJECT`, do not begin Definition or Execution without a **current closure-compatible accepted CPS**.
- An old accepted CPS that predates stronger Discovery Closure is historical lineage, not current preparation authority.
- If a missing material first-party component, missing observable runtime branch or stale CPS is discovered, transition to `DISCOVERY_REFRESH_REQUIRED`; do not absorb product reconstruction into Definition/Worker review.
- Discovery Authority is separate from Execution Authority. Passive/read-only discovery permission never grants code mutation, deploy or other execution permission.
- Generic private AIDOS runtime agents are defined once here; projects configure them rather than forking them.
- Reusable learning must be generalized and retain provenance/evidence.
- A generic heuristic may never silently override accepted Project Baseline, CPS, project truth, Definition or frozen Launch Definition.
- Once accepted launch criteria are satisfied, additional improvement alone is not sufficient grounds to delay release.
- Delaying after `RELEASE_READY` requires explicit Launch Definition/release-scope reopen with reason/consequence recorded.

## Preparation inheritance

```text
NEW_PROJECT
accepted Project Baseline
→ Definition

EXISTING_PROJECT
accepted Project Baseline
→ material product graph closed
→ accepted CPS under required closure contract
→ Definition
```

For existing projects the CPS includes the known materially relevant component/dependency graph and runtime observations. The primary repository is not assumed to equal the product boundary.

Current existing-project preparation requirement:

```text
Evidence Inventory 0.2.0
CPS 0.2.0
Discovery catalog 0.2.0
Discovery state ACCEPTED
open discovery blockers = 0
```

## Agent hierarchy

1. **Definition Agent** — consumes accepted preparation state, defines one desired delta/goal and obtains human acceptance.
2. **Worker Agent** — bounded planning, dispatch, review, CPS-staleness detection, release-scope discipline and state control.
3. **Execution Agent** — technical execution only inside exact accepted bindings and authority.

Project preparation happens before this hierarchy through AIDOS-Builder/AIDOS-Contracts.

## Knowledge selection

```text
AIDOS core
→ relevant capability knowledge
→ relevant goal-pattern knowledge
→ accepted Project Baseline
→ accepted closure-compatible CPS (EXISTING_PROJECT)
→ accepted Definition
→ accepted Launch Definition where applicable
→ current Execution
```

Do not bulk-load unrelated knowledge.

## Discovery refresh

When current-state preparation becomes invalid:

```text
DISCOVERY_REFRESH_REQUIRED
→ preserve old accepted CPS/evidence
→ AIDOS-Builder closes only missing branches
→ new CPS accepted
→ Definition consistency check
```

A product `CONTRADICTION` and a discovery closure gap are different states. Do not ask the human to make a product decision to compensate for missing objective discovery evidence.

## Launch governance

Use `protocols/LAUNCH_PROTOCOL.md`.

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

After scope freeze classify new findings only as `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED` and preserve non-blocking ideas in the post-launch backlog.

## Durable state

Chats/sessions are disposable. Essential state must be reconstructable from project-repository state/events.

AIDOS consumes but does not own/regenerate Project Baseline, Evidence Inventory, Discovery Authority, discovery state or CPS.

## Changes to AIDOS itself

Prefer:

```text
observed project fact
→ generalized candidate lesson
→ evidence/provenance review
→ proven knowledge
→ validator/tool/skill where possible
→ protocol simplification when justified
```

Executable prevention is preferred over longer prose when the same failure class can be machine-detected.
