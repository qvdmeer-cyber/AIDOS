# Execution protocol

## One execution, one bounded goal

An Execution exists to deliver one accepted development goal. Technical subtasks and repair loops do not become separate product goals merely because they require multiple steps.

For `EXISTING_PROJECT`, execution implements an accepted Definition **against a specific accepted Current Product State snapshot**. The Execution Agent may inspect current code to do the work, but it does not silently redefine the pre-execution product state.

For work inside a frozen release, execution is also bounded by the accepted Launch Definition/release scope. Execution Agent may not pull attractive `POST_LAUNCH` improvements into the active release merely because implementation makes them convenient.

## Required bindings

Every execution binds:

- `project_id` and `project_mode`;
- repository and official local root;
- branch/ref policy;
- accepted Project Baseline commit;
- for `EXISTING_PROJECT`: accepted Current Product State ID + accepted commit;
- `definition_id` + version;
- `execution_id` + revision;
- selected AIDOS core/capability/goal knowledge IDs/versions;
- execution model/profile;
- authority/capabilities;
- acceptance/evidence contract.

When a frozen Launch Definition applies, the execution additionally binds its release/Launch Definition identity once that machine-readable runtime contract is implemented.

## Preflight

Validate preparation, project/root and runtime bindings before altering project state.

Fail closed when:

- project/root/branch does not match;
- accepted baseline binding differs;
- an existing project has no accepted CPS binding;
- the requested CPS identity differs from the execution binding;
- other required execution authority is absent.

Wrong/stale preparation context must not be repaired by guessing.

## Consistency before build

Worker validates that the planned implementation and acceptance contract do not contradict:

- accepted Project Baseline;
- accepted Current Product State for an existing product;
- accepted Definition;
- frozen Launch Definition where applicable.

Execution Agent may choose implementation details inside that contract.

## Technical loop

Execution Agent owns the ordinary inspect/implement/test/diagnose/repair loop. Do not create GPT handoffs for milestones that are not terminal.

A newly discovered improvement outside frozen release scope is not an execution task. Report evidence through the normal handoff so Worker can classify it under `protocols/LAUNCH_PROTOCOL.md`.

## Current-state drift discovered during execution

Execution may uncover evidence that the accepted CPS was materially incomplete or stale before this execution began.

The Execution Agent should:

- preserve the evidence;
- continue technical work only when the accepted Definition remains unambiguous and safe;
- flag the discrepancy in the terminal handoff;
- not rewrite the CPS itself.

Worker decides whether the result is ordinary expected change caused by this execution or requires `DISCOVERY_REFRESH_REQUIRED` through AIDOS-Builder.

## Long-running work

Duration alone is not failure. A useful execution may run for hours. AIDOS tracks progress/evidence and repeated failure signatures rather than enforcing arbitrary wall-clock termination.

## Context-stuck handling

Initial thresholds are intentionally generous. Signals include repeated identical failures, oscillating fixes, repeatedly rejected hypotheses or persistent stale-instruction behaviour.

A fresh Codex session may retry the same accepted Execution when context failure is the plausible cause. Repeated fresh-context failure escalates to Worker reasoning/blocker handling rather than spawning endless sessions.
