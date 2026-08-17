# Learning protocol

## Purpose

AIDOS becomes more effective by learning from evidence across projects without importing project-specific truth into the global system or turning statistical correlation into an automatic system rule.

## Three-stage insight model

AIDOS distinguishes:

1. **Observation** — a pattern directly supported by recorded evidence/metrics.
2. **Hypothesis / learned lesson** — a plausible generalized explanation or improvement derived from observations, not yet system authority.
3. **Adopted improvement** — an explicitly reviewed/accepted change to AIDOS rules, profiles, contracts, protocols, validators or tools.

`schemas/system-insight.schema.json` represents this distinction.

A statistically recurring pattern may create an `OBSERVATION`; it must not silently mutate orchestration or development policy.

## Existing knowledge promotion ladder

After execution/review, notable knowledge is still classified as:

1. **Project fact** — remains only in the project repository.
2. **Learning candidate** — plausibly reusable hypothesis, not yet proven/generalized.
3. **Proven AIDOS knowledge** — evidence supports reuse beyond the source project.
4. **Toolized knowledge** — validator/script/skill enforces or automates the lesson.
5. **Protocol improvement** — structural AIDOS change prevents the failure class.

The existing `learning-candidate.schema.json` remains the promotion artifact for reusable hypotheses. A candidate/proven lesson does not become an adopted system change merely because it is statistically convincing.

## Adoption gate

A rule/profile/protocol change becomes an `ADOPTED_IMPROVEMENT` only when:

- the relevant observation/hypothesis and evidence are reviewable;
- scope and potential regressions are considered;
- the change is intentionally accepted through AIDOS governance;
- the exact resulting code/contract/profile change is referenced.

This preserves a clear difference between **what AIDOS noticed** and **what AIDOS chose to change**.

## Provenance

Every promoted learning records where applicable:

- stable ID;
- problem/profile/capability/goal classification;
- generalized statement;
- source project/workstream/execution(s);
- evidence references/hashes;
- validation method;
- confidence/status;
- first-seen and last-validated version/date;
- supersedes/deprecated relationships;
- adopted change reference when promoted into system behaviour.

## Portfolio evidence

Learning may use cross-project/workstream telemetry such as:

- repair frequency and first-pass acceptance;
- blocker/recovery classes;
- human intervention reasons;
- Definition gaps exposed during execution;
- queue/agent/human wait time;
- progress/ETA estimation error;
- profile/preset overrides and contradictions;
- repeated shared-resource/integration bottlenecks.

The maturity question is not simply "is human input decreasing?". AIDOS should track **what human attention is still required for** and whether it shifts from operational/technical intervention toward genuine product, risk and strategic decisions.

## Goal-scoped retrieval

AIDOS knowledge is not globally injected into every execution. Worker/Thinker selects the minimum relevant set by:

```text
core
+ applicable profiles/capabilities
+ development goal/pattern
+ workstream context
```

## Preference for executable knowledge

When practical:

```text
observation
→ hypothesis
→ proven lesson
→ validator/tool/skill
```

is preferred over repeatedly spending model context on prose instructions. Executable prevention must still pass the adoption gate before becoming authoritative AIDOS behaviour.
