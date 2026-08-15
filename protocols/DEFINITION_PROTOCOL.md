# Definition protocol

## Goal

Make foreseeable product acceptance explicit before implementation cost is incurred.

For release-bound work, also establish the quality threshold for going to real users **before launch pressure exists**.

## Minimum Definition content

A Definition should contain, as relevant:

- goal/problem statement;
- user-visible/product behaviour;
- actors/permissions;
- main flows;
- edge/error/empty states;
- data behaviour/lifecycle;
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

Questions should be skipped when canonical project sources already settle the answer reliably.

## Consistency gate

Before `ACCEPTED`, check:

- internal Definition contradictions;
- contradictions with canonical project truth;
- required behaviour without acceptance coverage;
- acceptance checks for behaviour not requested;
- hidden material assumptions;
- non-functional constraints that can invalidate the chosen behaviour.

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

An accepted Launch Definition is similarly immutable for that release. Reopening after scope freeze requires an explicit reason and new accepted version; subjective desire for further improvement is not an implicit reopen.
