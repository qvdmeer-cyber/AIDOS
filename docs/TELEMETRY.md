# Telemetry

AIDOS measures first and optimizes later.

## Per execution

Record where available:

- project/goal/execution/revision;
- Codex model and reasoning effort;
- Codex session ID and whether reused/rotated;
- input/cached-input/output/reasoning token counts;
- execution duration;
- repair cycles;
- terminal outcome;
- acceptance readiness/results;
- context-stuck signals;
- GPT review count/revisions;
- queue/wait time;
- peak/representative RAM, CPU and disk-free metrics;
- review artefact size/lifecycle;
- human interruptions/decision count.

## Primary optimization question

> How much correct, pre-accepted product progress is produced per hour of human attention and per unit of model allowance?

AIDOS should not optimize for maximum autonomy as an end in itself.

## V1 policy

- No wall-clock kill for productive Codex execution.
- Loop/usage thresholds start deliberately generous.
- Resource limits protect against concrete host damage/exhaustion rather than merely long work.
- Tighten thresholds only after real data shows allowance waste or recurring failure patterns.
