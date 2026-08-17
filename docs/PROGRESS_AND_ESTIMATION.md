# Progress and estimation

AIDOS may estimate project/workstream progress and remaining time, but estimates are not project truth.

> **Definition + evidence + validation/integration/release gates determine completion. Progress and ETA are probabilistic projections.**

Progress must not default to `completed task count / total task count`. Where evidence permits, use a weighted projection based on accepted Definition scope, workstreams, dependency graph, remaining weighted work, execution/revision state, deterministic validation, integration gates and release gates where applicable.

The machine-readable projection is `schemas/progress-estimate.schema.json`.

A project-level estimate may aggregate workstreams, but two locally complete workstreams do not make the project complete while integration remains pending.

## ETA

ETA confidence is explicit:

- `HIGH`
- `MEDIUM`
- `LOW`
- `NOT_RELIABLY_ESTIMABLE`

When estimable, include a point estimate and optional lower/upper range plus assumptions. `NOT_RELIABLY_ESTIMABLE` is preferable to false precision.

An estimate binds to exact project/workstream/Definition state at `estimated_at`. New evidence may invalidate it without changing project truth.

## Calibration

When the estimated scope completes, preserve actual remaining time from the estimate point so AIDOS can compare estimated versus actual duration. Repeated bias may be analyzed by archetype, stack, workstream type, blocker class or integration profile.

A statistical estimation pattern is an **Observation** first. It becomes a reusable rule only after hypothesis/review/adoption under the Learning Protocol.

An important maturity signal is not merely less human input, but whether human attention shifts from operational/technical intervention toward genuine product, risk and strategic decisions.
