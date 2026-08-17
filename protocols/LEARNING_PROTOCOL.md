# Learning protocol

## Purpose

AIDOS becomes more effective by learning from evidence across projects without importing project-specific truth into the global system or turning statistical correlation into an automatic system rule.

## Three-stage insight model

AIDOS distinguishes:

1. **Observation** — a pattern directly supported by recorded evidence/metrics.
2. **Hypothesis / learned lesson** — a plausible generalized explanation or improvement derived from observations, not yet system authority.
3. **Adopted improvement** — an explicitly reviewed/accepted change to AIDOS rules, profiles, contracts, protocols, validators or tools.

`schemas/system-insight.schema.json` represents this distinction.

A statistically recurring pattern may create an `OBSERVATION`; it must not silently mutate orchestration, decision authority or development policy.

## Auto Define learning

Auto Define produces useful evidence about where autonomous Definition/Baseline reasoning is reliable. Record/aggregate where available:

- decision authority class;
- confidence/reversibility/impact profile;
- Auto Decision count;
- later revision/supersession;
- human overrides and reasons;
- decision classes that remain stable;
- decision classes that often require later human intervention;
- Definition gaps exposed after autonomous closure.

Example maturity chain:

```text
Observation:
AUTO_DECIDABLE recovery-policy decisions with HIGH confidence were stable in 47/48 cases.

→ Hypothesis:
This class may be a good candidate for a more specific reusable profile/default.

→ explicit review/adoption

→ Adopted improvement:
versioned profile/validator/policy change
```

Forbidden shortcut:

```text
low override rate
→ automatically lower human-gate threshold
```

Auto Define statistics never automatically expand authority, permit material impacts, change reversibility requirements or downgrade `HUMAN_REQUIRED` categories.

## Existing knowledge promotion ladder

After execution/review, notable knowledge is still classified as:

1. **Project fact** — remains only in the project repository.
2. **Learning candidate** — plausibly reusable hypothesis, not yet proven/generalized.
3. **Proven AIDOS knowledge** — evidence supports reuse beyond the source project.
4. **Toolized knowledge** — validator/script/skill enforces or automates the lesson.
5. **Protocol improvement** — structural AIDOS change prevents the failure class.

The existing `learning-candidate.schema.json` remains the promotion artifact for reusable hypotheses. A candidate/proven lesson does not become an adopted system change merely because it is statistically convincing.

## Adoption gate

A rule/profile/protocol/decision-policy change becomes an `ADOPTED_IMPROVEMENT` only when:

- the relevant observation/hypothesis and evidence are reviewable;
- scope and potential regressions are considered;
- human-authority consequences are explicitly considered for decision-governance changes;
- the change is intentionally accepted through AIDOS governance;
- the exact resulting code/contract/profile change is referenced.

This preserves a clear difference between what AIDOS noticed and what AIDOS chose to change.

## Provenance

Every promoted learning records where applicable stable ID, classification, generalized statement, source project/workstream/execution/Definition decisions, evidence refs/hashes, validation method, confidence/status, dates/version and supersession/adoption references.

## Portfolio evidence

Learning may use cross-project/workstream telemetry such as repair frequency, first-pass acceptance, blocker/recovery classes, human intervention reasons, Definition gaps, Auto Decision stability/override rates, wait time, estimation error, profile overrides and shared-resource/integration bottlenecks.

The maturity question is not simply "is human input decreasing?". AIDOS should track **what human attention is still required for** and whether it shifts from operational/technical intervention toward genuine product, risk and strategic decisions.

## Goal-scoped retrieval

AIDOS knowledge is not globally injected into every execution. Worker/Thinker selects the minimum relevant set by core + applicable profiles/capabilities + development goal/pattern + workstream context.

## Preference for executable knowledge

When practical:

```text
observation
→ hypothesis
→ proven lesson
→ validator/tool/skill
```

is preferred over repeatedly spending model context on prose instructions. Executable prevention must still pass the adoption gate before becoming authoritative AIDOS behaviour.
