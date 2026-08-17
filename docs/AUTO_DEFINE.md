# Auto Define — confidence-driven autonomous Definition

## Purpose

Auto Define reduces low-value human elicitation without weakening authority, provenance or final Definition governance.

The target behaviour is:

```text
human states product intent
→ AIDOS resolves system/repository facts
→ AIDOS safely auto-decides eligible remaining project choices
→ only genuine human-required decisions are surfaced
→ after each human answer, rerun Auto Define to a fixed point
→ human reviews/accepts the converged Definition
```

Auto Define is not a question-skipping mode. It is an authority- and risk-governed decision capability.

## Shared authority contract

AIDOS Core consumes the shared AIDOS-Contracts Decision Governance contract:

```text
SYSTEM_INVARIANT
REPO_VERIFIABLE
AUTO_DECIDABLE
HUMAN_REQUIRED
```

Resolution:

```text
SYSTEM_INVARIANT
→ resolve from AIDOS contract/governance source
→ no project preference question

REPO_VERIFIABLE
→ resolve from authorized project-local canonical evidence
→ provenance required

AUTO_DECIDABLE
→ Decision Assessment
→ AUTO_DECISION only when policy passes
→ otherwise HUMAN_REQUIRED

HUMAN_REQUIRED
→ durable Human Input Request
```

System invariants and repository facts are **not Auto Decisions**. Only a genuine project choice classified `AUTO_DECIDABLE` produces `AUTO_DECISION`.

## Confidence is necessary, not sufficient

Auto Define considers:

- confidence;
- reversibility;
- blast radius;
- product/business impact;
- security/privacy impact;
- destructive impact;
- external cost/commitment;
- compatibility impact;
- authority boundary;
- missing evidence;
- materially equivalent alternatives.

The shared policy currently permits an Auto Decision only when all material impacts/evidence gaps are at most `LOW`, it is inside authority, no materially equivalent alternative remains, and:

- confidence is `HIGH`; or
- confidence is `MEDIUM` **and** reversibility is `REVERSIBLE`.

`LOW`, `IRREVERSIBLE`, outside-authority or material-impact decisions require human input.

Confidence never allows AIDOS to cross an authority boundary.

## Real decision space

Do not manufacture A/B decisions. Record the actual material alternatives. There may be zero explicit alternatives because accepted constraints imply one reasonable implementation, or there may be several.

When two or more materially equivalent choices remain and the difference represents project preference rather than evidence-backed consequence, Auto Define must escalate to human input.

## Durable Definition Auto Decision

Definition Auto Decisions are stored under:

```text
.aidos/definitions/<definition_id>/v<version>/decisions/<decision_id>.json
```

The record follows AIDOS-Contracts `schemas/auto-decision.schema.json` and includes exact project/Definition binding, target surface/field, chosen value, alternatives, rationale, Decision Assessment, evidence/source refs, actor/model/session attribution and supersession lineage.

Affected `PROGRESS.json` surfaces reference the durable decision. A GPT explanation is never the only record of why a surface closed.

## Explainability

A client may later render, for example:

```text
Auto-defined because:
- confidence HIGH
- follows accepted private-tailnet constraint
- no materially equivalent product alternative
- reversible implementation decision
```

This explanation is generated from the persisted assessment/rationale, not reconstructed from chat history.

## Fixed-point pass

At Definition start/resume and after every new human decision/evidence change:

```text
repeat
  inspect unresolved applicable surfaces/items
  classify authority
  resolve SYSTEM_INVARIANT
  resolve REPO_VERIFIABLE
  persist policy-valid AUTO_DECIDABLE decisions
until no additional item can be safely resolved

if material unresolved HUMAN_REQUIRED exists
  publish exactly one Human Input Request
else
  proceed to Definition consistency/review gate
```

A human answer may resolve constraints that make several later questions auto-decidable; therefore AIDOS must rerun the whole remaining decision set rather than blindly ask the next precomputed question.

## Human Input escalation

Human Input Requests are the fail-closed destination for:

- `HUMAN_REQUIRED` authority;
- low confidence;
- insufficient evidence;
- materially equivalent alternatives;
- material product/business/security/privacy/destructive/cost/compatibility/blast-radius impact;
- irreversible decisions;
- authority uncertainty/conflict.

The request should carry the assessment/evidence explaining why Auto Define stopped. Options reflect the actual decision space.

## Override and supersession

Auto Decisions are version-bound and revisable, not immutable global truth.

When new evidence or human direction invalidates one:

1. preserve the prior record;
2. create a replacement decision or new Definition version;
3. link `supersedes_decision_id` / `superseded_by` where applicable;
4. reopen affected Definition surfaces;
5. rerun Auto Define and convergence validation.

A human override remains distinguishable from the earlier autonomous choice.

## Definition acceptance remains human governance

Auto Define can close all foreseeable Definition details without asking intermediate questions, but it does **not** silently convert a proposed Definition into `ACCEPTED`.

The existing explicit human Definition acceptance gate remains authoritative before execution. Auto Define optimizes how the Definition converges, not who authorizes the resulting product delta.

## Baseline boundary

Project Baseline Auto Define is implemented by AIDOS-Builder using the same shared Decision Governance contract. Core does not reimplement Baseline completeness.

## Telemetry and learning

Record at least:

- total Auto Decisions per Definition;
- confidence distribution;
- later revisions/supersessions;
- revision reason;
- human overrides;
- authority/decision classes that remain stable;
- classes that frequently require later human intervention;
- Human Input Requests avoided/required where measurable.

This feeds the existing maturity chain:

```text
OBSERVATION
→ HYPOTHESIS
→ explicit adoption
```

Statistics must never automatically expand authority, lower impact thresholds or remove human gates.
