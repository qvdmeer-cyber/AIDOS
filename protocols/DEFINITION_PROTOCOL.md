# Definition protocol

## Goal

Make foreseeable product acceptance explicit before implementation cost is incurred.

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

## Reopen

A Definition is immutable once accepted except through a new version. Implementation contradiction produces `REOPENED`, preserving prior accepted lineage and evidence for why it changed.
