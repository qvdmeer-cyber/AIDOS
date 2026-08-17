# Definition protocol

## Goal

Make the desired product delta complete enough for explicit human acceptance before execution, while minimizing low-value human elicitation through **Auto Define**.

For an existing product, Definition is the desired delta from accepted current product state, not a reconstruction of existing behaviour.

## Preparation gate

```text
NEW_PROJECT
accepted Project Baseline
→ Definition

EXISTING_PROJECT
accepted Project Baseline
+ Discovery Closure PASS
+ accepted CPS 0.3.0 / discovery catalog 0.3.0
→ Definition
```

A stale/missing current-state branch returns to AIDOS-Builder; Definition does not compensate with guesses or human questions.

## Decision authority before elicitation

For every unresolved Definition concern, classify authority before asking the human:

```text
SYSTEM_INVARIANT
REPO_VERIFIABLE
AUTO_DECIDABLE
HUMAN_REQUIRED
```

Normative semantics and autonomy policy come from AIDOS-Contracts Decision Governance 0.1.0.

### SYSTEM_INVARIANT

Resolve from AIDOS governance/contracts with source provenance. It is not a project preference and cannot be overridden inside a project Definition.

### REPO_VERIFIABLE

Resolve objectively from authorized project-local canonical truth/evidence. Persist source/evidence refs. Plausible inference without sufficient evidence does not close the concern.

### AUTO_DECIDABLE

This is a genuine project choice, but AIDOS may decide it autonomously only after a Decision Assessment proves the shared policy permits it.

Current policy requires:

- confidence `HIGH`, or `MEDIUM` plus `REVERSIBLE`;
- inside authority;
- no materially equivalent competing alternative;
- product/business, security/privacy, destructive, external-cost/commitment, compatibility and blast-radius impact all at most `LOW`;
- missing evidence at most `LOW`;
- never `LOW` confidence or irreversible.

Persist a first-class `AUTO_DECISION` before using the choice as Definition truth.

### HUMAN_REQUIRED

Publish a durable Human Input Request. This includes direct `HUMAN_REQUIRED` classification and any `AUTO_DECIDABLE` concern that fails confidence/reversibility/impact/authority/evidence/alternative policy.

## Real decision space

Do not manufacture A/B choices. The option set must match reality. It may contain zero explicit alternatives, one material competitor, two, three or more.

If multiple materially equivalent alternatives remain and selection expresses project preference rather than an evidence-backed consequence, require human input.

## Auto Define fixed-point pass

Run Auto Define:

- when a Definition starts;
- whenever it resumes in a new/rotated session;
- after each human answer;
- after material new evidence;
- after superseding/reopening a decision.

Algorithm:

```text
repeat
  inspect all unresolved applicable concerns
  classify authority
  resolve SYSTEM_INVARIANT
  resolve REPO_VERIFIABLE
  assess + persist policy-valid AUTO_DECIDABLE choices
  update Definition/applicability/progress
until no additional concern can close safely

if HUMAN_REQUIRED remains
  publish exactly one Human Input Request
else
  proceed to consistency/review
```

AIDOS must not keep a stale precomputed question queue. One human answer can constrain several later decisions enough to auto-resolve them.

## Durable Auto Decision

Definition decisions live under:

```text
.aidos/definitions/<definition_id>/v<version>/decisions/<decision_id>.json
```

Auto Decisions follow AIDOS-Contracts `schemas/auto-decision.schema.json` and bind:

- project + Definition version;
- target surface/field;
- chosen value;
- actual alternatives considered;
- rationale;
- Decision Assessment;
- evidence/source refs;
- actor/model/session;
- time;
- supersession lineage.

Use `tools/New-AidosDefinitionAutoDecision.ps1` and validate with `tools/Test-AidosAutoDecision.ps1` where available.

A hidden model inference is never an equivalent substitute.

## Project and Definition applicability

Project Applicability identifies which development surfaces exist/may exist. Definition Applicability identifies which are affected by the current desired delta.

Durable projections:

```text
.aidos/profile/PROJECT_APPLICABILITY.json
.aidos/definitions/<definition_id>/v<version>/APPLICABILITY.json
```

Profiles remain accelerators, not truth. Verified/accepted project truth wins. A project-applicable surface cannot be silently omitted while delta applicability remains unresolved.

## Definition surface progress

The current fixed convergence catalog remains `catalog/definition-surfaces.catalog.json` with 13 surfaces. Each is `COMPLETE`, `NOT_APPLICABLE`, `INCOMPLETE`, `DECISION_REQUIRED` or `BLOCKED`.

Durable progress:

```text
.aidos/definitions/<definition_id>/v<version>/PROGRESS.json
```

Progress tracks decision/source refs and now distinguishes the latest human/auto/system/repository resolution metadata. Chat history is not progress state.

## Transaction after every resolution

For human, auto, system or repository resolution:

```text
persist authoritative record/provenance
→ update affected Definition/applicability surfaces
→ bind decision/source refs
→ recalculate PROGRESS.json
→ validate
→ rerun Auto Define to fixed point
```

After **every human decision**, additionally render the current full per-surface Definition progress before asking any next Human Input question.

If persistence or validation fails, do not advance.

## Human Input Request escalation

When Auto Define stops at a human boundary, persist a Human Input Request containing exact Definition binding, actual material options, evidence refs and—where relevant—authority classification, assessment ref and Auto Define stop reason.

After resolution, AIDOS activates the Definition Thinker again from durable state and immediately reruns Auto Define.

## Minimum Definition content

As applicable, Definition covers goal/scope, current-state delta, functional behaviour, actors/permissions, flows, edge/error states, data lifecycle, security/privacy, compatibility/performance/runtime, observability/recovery, acceptance coverage, out-of-scope and unresolved assumptions.

A concern may be omitted only through resolved applicability or justified `NOT_APPLICABLE` state.

## Review gate

Before `USER_REVIEW`:

- `Test-AidosDefinitionProgress.ps1 -RequireReady` passes;
- no material Definition applicability remains `DECISION_REQUIRED`;
- every decision-backed closure has durable provenance;
- current non-superseded Auto Decisions validate under Decision Governance;
- no system invariant has been treated as project-overridable;
- no material hidden assumption remains;
- Definition is internally consistent with Baseline/CPS and acceptance coverage.

The deterministic validator proves coverage and decision-policy integrity, not product desirability.

## Final acceptance

Auto Define optimizes convergence. It does **not** silently authorize execution.

The converged Definition still goes to explicit human review/acceptance. Only `ACCEPTED` Definition may authorize execution planning.

## Override / correction

When new evidence or human direction invalidates an Auto Decision:

1. preserve old decision evidence;
2. persist replacement/human decision or new Definition version;
3. link supersession lineage;
4. reopen affected surfaces;
5. rerun Auto Define and convergence validation.

Do not rewrite history in place.

## Discovery conflicts

Known CPS `CONFLICT`/`DRIFT` can be accepted current truth. A material missing component/runtime/content branch is instead `DISCOVERY_REFRESH_REQUIRED` and routes to Builder.

## Launch Definition

Launch Definition/release governance remains separately explicit and human accepted. Auto Define may resolve low-risk details inside accepted release boundaries but cannot weaken accepted launch criteria, expand authority or redefine material release risk autonomously.

## Session continuity

A new Definition session loads canonical project truth, Definition/applicability/progress, durable decision records and open Human Input Requests. It does not rely on predecessor chat summaries for authority.

See `docs/AUTO_DEFINE.md`.
