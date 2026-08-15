# Definition protocol

## Goal

Make foreseeable product acceptance explicit before implementation cost is incurred.

For an existing product, Definition specifies the **desired delta from an accepted Current Product State**, not a fresh reconstruction of what already exists.

For release-bound work, also establish the quality threshold for going to real users **before launch pressure exists**.

## Preparation gate

```text
NEW_PROJECT
accepted Project Baseline
→ Definition

EXISTING_PROJECT
accepted Project Baseline
+ accepted Current Product State
→ Definition
```

If existing-product discovery is missing/stale or materially contradicted by evidence, refresh AIDOS-Builder discovery rather than absorbing that discovery into goal Definition.

## Minimum Definition content

A Definition should contain, as relevant:

- goal/problem statement;
- current-state references relevant to the goal;
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

The Definition Agent asks one material decision at a time. The next question may depend on the answer. The objective is decision quality, not questionnaire throughput.

Questions must be skipped when the accepted Project Baseline/Current Product State or other canonical project truth already settles the answer reliably.

Existing capability discovery is not a Definition question. Definition asks only what should change.

## Current-state conflict/drift

Accepted Current Product State may contain known `CONFLICT` or `DRIFT` because that discrepancy is itself current truth.

If the goal touches that area:

- surface the known evidence/state;
- distinguish current uncertainty from desired future behaviour;
- ask only the product decision needed for the future state;
- route a materially incomplete/incorrect current-state snapshot back to Existing Project Discovery.

## Consistency gate

Before `ACCEPTED`, check:

- internal Definition contradictions;
- contradictions with accepted Project Baseline/current-state evidence;
- required behaviour without acceptance coverage;
- acceptance checks for behaviour not requested;
- hidden material assumptions;
- non-functional constraints that can invalidate the chosen behaviour;
- accidental re-specification of unchanged existing functionality.

## Launch Definition / Release Gate

When a product or material release is expected to reach real users, establish a separate release-scoped Launch Definition before the final development phase wherever practical.

It defines the falsifiable threshold for release readiness and explicitly freezes release scope after acceptance.

Required principle:

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

The Launch Definition should identify:

- core promise/critical flows required at launch;
- objective security/privacy/data-integrity/compliance blockers;
- required reliability/compatibility/deployment conditions;
- launch evidence/validators;
- deliberately deferred/out-of-scope improvements;
- intended release/audience/environment;
- human acceptance/version.

After acceptance, new findings are governed by `protocols/LAUNCH_PROTOCOL.md` and classified as `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`.

## Reopen

A Definition is immutable once accepted except through a new version. Implementation contradiction produces `REOPENED`, preserving prior accepted lineage and evidence for why it changed.

If the contradiction actually means the accepted Current Product State is stale/wrong, refresh discovery instead of rewriting history through Definition.

An accepted Launch Definition is similarly immutable for that release. Reopening after scope freeze requires an explicit reason and new accepted version; subjective desire for further improvement is not an implicit reopen.
