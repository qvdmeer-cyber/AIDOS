# Definition protocol

## Goal

Make foreseeable product acceptance explicit before implementation cost is incurred.

For an existing product, Definition specifies the **desired delta from a closure-compatible accepted Current Product State**, not a fresh reconstruction of what already exists.

For release-bound work, also establish the quality threshold for going to real users **before launch pressure exists**.

## Preparation gate

```text
NEW_PROJECT
accepted Project Baseline
→ Definition

EXISTING_PROJECT
accepted Project Baseline
+ Discovery Closure PASS
+ accepted current CPS
→ Definition
```

Current existing-project preparation requires CPS contract/discovery catalog `0.2.0`, accepted discovery state and zero open discovery blockers.

If discovery is missing, `DISCOVERY_REFRESH_REQUIRED`, based on an incompatible older contract, or materially contradicted by new evidence, return to AIDOS-Builder rather than absorbing product reconstruction into Definition.

The primary repository is not assumed to represent the whole current product; Definition relies on the accepted CPS material component/dependency graph.

## Minimum Definition content

A Definition should contain, as relevant:

- goal/problem statement;
- current-state component/capability/flow references relevant to the goal;
- explicit desired change/delta;
- user-visible/product behaviour after the change;
- actors/permissions;
- main changed/new flows;
- edge/error/empty states;
- data behaviour/lifecycle change;
- security/privacy constraints;
- compatibility/performance/runtime constraints;
- observability/recovery expectations;
- acceptance checks;
- explicit out-of-scope;
- unresolved assumptions (must be non-material before acceptance);
- source/provenance references for derived facts;
- human acceptance timestamp/version.

## One-question elicitation

Ask one material decision at a time. Skip questions already settled reliably by the accepted Project Baseline, closure-compatible CPS or canonical project truth.

Existing capability/component/runtime discovery is not a Definition question. Definition asks only what should change.

## Current-state conflict/drift/closure gaps

Accepted CPS may contain known `CONFLICT` or `DRIFT` because that discrepancy can itself be current truth.

If a goal touches such an area, surface it and ask only the desired future-state decision.

A **Discovery Closure gap** is different. Examples:

- omitted material first-party component;
- unclosed first-party material dependency;
- known public/passive runtime missing observation;
- materially stale/incorrect CPS fact.

These route to:

```text
DISCOVERY_REFRESH_REQUIRED
→ AIDOS-Builder
→ close missing current-state branch
→ accept new CPS
→ Definition consistency check
```

Do not ask the human to invent a product decision as a substitute for objective discovery.

## Consistency gate

Before `ACCEPTED`, check:

- internal Definition contradictions;
- contradictions with accepted Project Baseline/CPS evidence;
- required behaviour without acceptance coverage;
- acceptance checks for behaviour not requested;
- hidden material assumptions;
- non-functional constraints that can invalidate behaviour;
- accidental re-specification of unchanged existing functionality;
- preparation/CPS binding still valid and closure-compatible.

## Launch Definition / Release Gate

When a product/material release is expected to reach real users, establish a release-scoped Launch Definition before the final development phase where practical.

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

The Launch Definition identifies core launch promise/flows, material security/privacy/data-integrity/compliance conditions, required reliability/compatibility/deployment, launch evidence, deliberate deferred scope, release/audience/environment and human acceptance/version.

After acceptance, new findings are classified as `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`.

## Reopen

Definition is immutable once accepted except through a new version.

- Desired future requirement contradiction → reopen Definition.
- Pre-existing current-product discovery/closure failure → refresh CPS first.
- Launch gate change after scope freeze → explicit Launch Definition reopen/version.

Preserve lineage in all cases.
