# Telemetry, observability and insights

AIDOS measures first and optimizes later. Telemetry is evidence for operations, estimation and learning; it does not automatically change system policy.

## Per Definition / Auto Define

Record where available:

- Definition ID/version;
- unresolved concerns assessed;
- authority classifications (`SYSTEM_INVARIANT`, `REPO_VERIFIABLE`, `AUTO_DECIDABLE`, `HUMAN_REQUIRED`);
- Auto Decisions count;
- Auto Decision confidence distribution;
- reversibility distribution;
- human gates caused by low confidence, material impact, missing evidence, equivalent alternatives, irreversibility or authority limits;
- Auto Decisions later revised/superseded;
- reason for revision;
- human overrides of Auto Decisions;
- time/question count avoided where measurable;
- Definition surfaces first exposed as incomplete during later execution despite Auto Define.

The most useful Auto Define reliability metric is not raw autonomy. It is the proportion of autonomous decisions that remain valid under later evidence/review, broken down by decision class and impact context.

## Per execution / revision

Record where available:

- project/workstream/goal/execution/revision;
- model/reasoning profile and session identity/rotation;
- token/allowance usage;
- execution duration;
- repair cycles;
- terminal outcome;
- deterministic validation result;
- first-pass acceptance versus repair;
- GPT/Thinker review count;
- queue/wait time;
- human interruptions/input requests and reasons;
- blocker/recovery events;
- representative resource metrics;
- review artefact lifecycle;
- Definition gaps first exposed during execution.

## Project/workstream insights

Aggregate where useful:

- executions/revisions per workstream;
- repair frequency and first-pass acceptance;
- blocker and recovery frequency/types;
- human interventions and reason classes;
- time spent waiting for human versus waiting for agent/resource/dependency;
- phase/workstream throughput and duration;
- integration-gate failures/retries;
- Definition surfaces or assumptions repeatedly reopened during execution;
- Auto Decision revision/override rate by authority/decision class;
- estimate-versus-actual remaining time.

## Portfolio/AIDOS-level insights

AIDOS may aggregate across isolated projects without mixing project-specific truth into another project's context. Portfolio metrics include:

- active projects/workstreams and local concurrency;
- human interventions over time;
- autonomy trend;
- **Auto Define stability by decision class/confidence**;
- human override reasons;
- first-pass reliability;
- repair frequency;
- blocker/recovery taxonomy;
- waiting-for-human versus waiting-for-agent/resource;
- recurring dependency/integration bottlenecks;
- estimation calibration;
- profile/preset effectiveness.

The primary maturity question is:

> **Where does AIDOS still need human attention, and is that attention moving over time from operational/technical problems toward genuine product, risk and strategic decisions?**

Low human-input count alone is not a success metric. A high Auto Define rate with frequent later correction is worse than selective autonomy with stable decisions.

## Progress/ETA evidence

Progress and ETA use `schemas/progress-estimate.schema.json` and the rules in `docs/PROGRESS_AND_ESTIMATION.md`.

Estimates are projections, not acceptance evidence. Preserve estimate timestamps/confidence and, after completion, actual remaining duration so calibration can improve.

## Insight maturity

Metrics/patterns may be persisted as `OBSERVATION` objects under `schemas/system-insight.schema.json`.

```text
telemetry/evidence
→ OBSERVATION
→ HYPOTHESIS
→ explicit review/adoption
→ ADOPTED_IMPROVEMENT
```

Auto Define telemetry follows the same boundary. A lower override rate may justify a hypothesis that a decision class is safe, but it **never automatically expands authority, lowers impact thresholds or removes a human gate**.

## Primary optimization question

> How much correct, pre-accepted product progress is produced per hour of human attention and per unit of model allowance, without weakening Definition/validation/release gates?

## Runtime policy

- No wall-clock kill for productive bounded Codex execution.
- Loop/usage thresholds start deliberately generous.
- Resource limits protect against concrete host damage/exhaustion.
- Tighten thresholds only after evidence shows waste or recurring failure.
