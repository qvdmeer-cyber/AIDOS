# Execution protocol

## One execution, one bounded goal

An Execution exists to deliver one accepted development goal. Technical subtasks and repair loops do not become separate product goals merely because they require multiple steps.

For `EXISTING_PROJECT`, execution implements an accepted Definition **against a specific closure-compatible accepted Current Product State**. The Execution Agent may inspect current code to perform the work, but it does not silently redefine pre-execution product state.

For frozen releases, execution is additionally bounded by the accepted Launch Definition/release scope.

## Required bindings

Every execution binds:

- `project_id` and `project_mode`;
- repository, official local root and branch/ref policy;
- accepted Project Baseline commit;
- for `EXISTING_PROJECT`:
  - accepted CPS ID + commit;
  - CPS contract version;
  - discovery catalog version;
- `definition_id` + version;
- `execution_id` + revision;
- selected relevant AIDOS knowledge;
- execution model/profile;
- authority/capabilities;
- acceptance/evidence contract.

Current existing-project execution requires CPS contract `0.2.0` and discovery catalog `0.2.0`.

## Preflight

Validate preparation, project/root and runtime bindings before altering project state.

Fail closed when:

- project/root/branch does not match;
- accepted baseline binding differs;
- existing project has no current accepted Discovery Closure/CPS binding;
- discovery state is `DISCOVERY_REFRESH_REQUIRED`/not `ACCEPTED`;
- CPS contract/catalog versions differ from required versions;
- CPS identity/commit differs from execution binding;
- other required execution authority is absent.

Wrong/stale preparation context must not be repaired by guessing.

## Consistency before build

Worker verifies the implementation plan/acceptance contract against:

- accepted Project Baseline;
- accepted closure-compatible CPS for existing products;
- accepted Definition;
- frozen Launch Definition where applicable.

Execution Agent chooses implementation details only inside that contract.

## Technical loop

Execution Agent owns ordinary inspect/implement/test/diagnose/repair work. Do not create GPT handoffs for non-terminal milestones.

A newly discovered improvement outside frozen release scope is not an execution task; report it for Worker classification.

## Discovery Closure gaps discovered during execution

Execution may reveal that the pre-execution CPS omitted objective current-product state, for example:

- an unmodeled material first-party codebase/service;
- a first-party material dependency chain not closed;
- a known public runtime branch absent/unobserved;
- material source/runtime reference not represented in CPS.

The Execution Agent should:

- preserve precise evidence;
- not update/rewrite CPS itself;
- not interpret the gap as a new product requirement;
- continue only when the accepted Definition remains unambiguous and safe;
- flag the closure discrepancy in terminal evidence.

Worker determines whether the evidence is an expected change caused by this execution or requires `DISCOVERY_REFRESH_REQUIRED` through AIDOS-Builder.

Discovery/read authority does not grant Execution Agent mutation authority beyond the Execution envelope.

## Long-running work

Duration alone is not failure. Track objective progress/evidence and repeated failure signatures rather than arbitrary wall-clock timeouts.

## Context-stuck handling

Thresholds are initially generous. A fresh Codex session may retry the same accepted Execution when context failure is plausible; repeated fresh-context failure escalates rather than spawning unlimited sessions.
