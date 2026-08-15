# Execution protocol

## One execution, one bounded goal

An Execution exists to deliver one accepted development goal. Technical subtasks and repair loops do not become separate product goals merely because they require multiple steps.

For work inside a frozen release, execution is also bounded by the accepted Launch Definition/release scope. Execution Agent may not pull attractive `POST_LAUNCH` improvements into the active release merely because implementation makes them convenient.

## Required bindings

Every execution binds:

- `project_id`;
- repository and official local root;
- branch/ref policy;
- `definition_id` + version;
- `execution_id` + revision;
- selected AIDOS core/capability/goal knowledge IDs/versions;
- execution model/profile;
- authority/capabilities;
- acceptance/evidence contract.

When a frozen Launch Definition applies, the execution will additionally bind its release/Launch Definition identity once that machine-readable runtime contract is implemented.

## Preflight

Validate bindings and runtime before altering project state. Wrong root/project is a hard fail-closed condition.

## Consistency before build

Worker validates that the planned implementation and acceptance contract do not contradict the accepted Definition. For release-scoped work it also validates that planned work is inside the frozen Launch Definition.

Execution Agent may choose implementation details inside that contract.

## Technical loop

Execution Agent owns the ordinary inspect/implement/test/diagnose/repair loop. Do not create GPT handoffs for milestones that are not terminal.

A newly discovered improvement outside frozen release scope is not an execution task. Report evidence through the normal handoff so Worker can classify it under `protocols/LAUNCH_PROTOCOL.md`.

## Long-running work

Duration alone is not failure. A useful execution may run for hours. AIDOS tracks progress/evidence and repeated failure signatures rather than enforcing arbitrary wall-clock termination.

## Context-stuck handling

Initial thresholds are intentionally generous. Signals include repeated identical failures, oscillating fixes, repeatedly rejected hypotheses or persistent stale-instruction behaviour.

A fresh Codex session may retry the same accepted Execution when context failure is the plausible cause. Repeated fresh-context failure escalates to Worker reasoning/blocker handling rather than spawning endless sessions.
