# Definition protocol

## Goal

Make foreseeable product acceptance explicit before implementation cost is incurred.

For an existing product, Definition specifies the **desired delta from a closure-compatible accepted Current Product State**, not a fresh reconstruction of what already exists.

For release-bound work, also establish the quality threshold for going to real users **before launch pressure exists**.

## Preparation gate

```text
NEW_PROJECT
accepted Project Baseline
→ Definition

EXISTING_PROJECT
accepted Project Baseline
+ Discovery Closure PASS
+ accepted current CPS
→ Definition
```

Current existing-project preparation requires CPS contract/discovery catalog `0.2.0`, accepted discovery state and zero open discovery blockers.

If discovery is missing, `DISCOVERY_REFRESH_REQUIRED`, based on an incompatible older contract, or materially contradicted by new evidence, return to AIDOS-Builder rather than absorbing product reconstruction into Definition.

The primary repository is not assumed to represent the whole current product; Definition relies on the accepted CPS material component/dependency graph.

## Project and Definition applicability

AIDOS may resolve reusable project applicability from versioned profile presets before asking Definition questions.

Profile composition:

```text
PRODUCT_ARCHETYPE
+ zero/more CAPABILITY
+ zero/more INTEGRATION
+ zero/more STACK
+ zero/more INFRASTRUCTURE
+ zero/more EXPOSURE_RISK
→ PROJECT_APPLICABILITY
```

Exactly one `PRODUCT_ARCHETYPE` identifies what/where the product fundamentally is. A capability describes what it can do; an integration describes an external provider/system it communicates with. Calling OpenAI therefore does not make a web/mobile/API product a `CHATGPT_APP`; it composes the `OPENAI_API` integration with its actual archetype.

Reusable development surfaces are owned by:

```text
catalog/development-surfaces.catalog.json
```

and composed presets by:

```text
catalog/profile-presets.catalog.json
```

The durable project projection is:

```text
.aidos/profile/PROJECT_APPLICABILITY.json
```

Profiles classify project development surfaces as `APPLICABLE`, `CONDITIONAL` or `NOT_APPLICABLE`, but they are **hypotheses/accelerators rather than project truth**.

Precedence:

```text
verified current project evidence / explicit accepted project decision
> explicit project applicability override
> composed preset result
> generic AIDOS heuristic
```

For each Definition version maintain:

```text
.aidos/definitions/<definition_id>/v<version>/APPLICABILITY.json
```

Project applicability answers which development surfaces exist/may exist in the product. Definition applicability separately classifies whether each relevant project surface is `AFFECTED`, `NOT_AFFECTED` or still `DECISION_REQUIRED` for the requested delta. A project-level `NOT_APPLICABLE` surface is automatically outside the Definition.

This is a coverage control: a project-applicable surface may not be silently omitted until its delta applicability is durably resolved.

Six Definition concerns are always core regardless of product shape:

1. goal/scope;
2. current state and desired delta;
3. intended functional behaviour;
4. acceptance coverage;
5. out of scope;
6. unresolved assumptions.

Conditional development surfaces supplement these core concerns. The current 13-surface progress contract remains the active convergence gate until explicitly versioned; applicability should be used to close irrelevant current surfaces with durable `NOT_APPLICABLE` rationale and to avoid asking irrelevant questions.

See `docs/PROFILE_PRESETS.md`.

## Definition surface catalog

Definition completeness/progress is tracked against the fixed private AIDOS catalog:

```text
catalog/definition-surfaces.catalog.json
```

Current surfaces:

1. `goal_scope`
2. `current_state_delta`
3. `functional_behavior`
4. `actors_permissions`
5. `main_flows`
6. `edge_error_states`
7. `data_lifecycle`
8. `security_privacy`
9. `compatibility_performance_runtime`
10. `observability_recovery`
11. `acceptance_coverage`
12. `out_of_scope`
13. `unresolved_assumptions`

Each surface has one explicit state:

- `COMPLETE`
- `NOT_APPLICABLE`
- `INCOMPLETE`
- `DECISION_REQUIRED`
- `BLOCKED`

Only `COMPLETE` and justified `NOT_APPLICABLE` count as complete.

## Durable progress object

For every Definition version, maintain project-local state at:

```text
.aidos/definitions/<definition_id>/v<version>/PROGRESS.json
```

The object conforms to `schemas/definition-progress.schema.json` and stores, per surface:

- status;
- concise current summary;
- decision references;
- source references;
- open-question count;
- update timestamp.

It also stores total complete/incomplete counts, next incomplete surface and the last human decision identity/time.

Chats are not the source of Definition progress. A rotated/reset/new Definition chat resumes from durable Definition state + `PROGRESS.json` + `APPLICABILITY.json` when present.

## Minimum Definition content

A Definition should contain, as relevant:

- goal/problem statement;
- current-state component/capability/flow references relevant to the goal;
- explicit desired change/delta;
- user-visible/product behaviour after the change;
- actors/permissions;
- main changed/new flows;
- edge/error/empty states;
- data behaviour/lifecycle change;
- security/privacy constraints;
- compatibility/performance/runtime constraints;
- observability/recovery expectations;
- acceptance checks;
- explicit out-of-scope;
- unresolved assumptions (must be non-material before acceptance);
- source/provenance references for derived facts;
- human acceptance timestamp/version.

These concerns map to the fixed Definition surfaces above. A concern may be `NOT_APPLICABLE` only with an explicit durable rationale.

## One-question elicitation

Ask one material decision at a time. Skip questions already settled reliably by the accepted Project Baseline, closure-compatible CPS, canonical project truth or resolved applicability.

Existing capability/component/runtime discovery is not a Definition question. Definition asks only what should change.

### Mandatory transaction after every human decision

A human answer is not considered fully consumed until the following transaction completes:

```text
human decision
→ persist decision
→ update affected Definition applicability when needed
→ update affected Definition surfaces
→ recalculate PROGRESS.json
→ validate applicability/progress structure and counts
→ render current progress for every surface
→ ask next single material question
```

If persistence/progress update fails, do **not** advance to the next decision question.

The visible progress must be generated from the newly persisted progress object. It must not be reconstructed from conversational memory.

Required compact rendering pattern:

```text
Definition vN · X/13 complete
✓ Goal and scope
✓ Current state and desired delta
○ Functional behaviour · incomplete
△ Actors and permissions · decision required
...
Next surface: actors_permissions
```

Rendering symbols:

- `✓` `COMPLETE`
- `—` `NOT_APPLICABLE`
- `○` `INCOMPLETE`
- `△` `DECISION_REQUIRED`
- `!` `BLOCKED`

Show every surface after every human decision. The progress display is intentionally repetitive because it is an explicit convergence/control surface, not conversational decoration.

## Progress validation and review gate

`tools/Test-AidosDefinitionProgress.ps1` (or an equivalent implementation of the same catalog rules) validates:

- Definition/project/version binding;
- exactly one entry for every catalog surface;
- only permitted statuses;
- stored complete/incomplete totals equal calculated totals;
- `next_surface` equals the first remaining incomplete surface;
- `DECISION_REQUIRED`/`BLOCKED` surfaces contain explanatory state.

Before `USER_REVIEW` / proposed acceptance:

```text
Test-AidosDefinitionProgress -RequireReady
```

must pass, meaning all 13 surfaces are `COMPLETE` or justified `NOT_APPLICABLE`.

In addition, no material project development surface may remain `DECISION_REQUIRED` in `APPLICABILITY.json`.

This validator proves Definition **coverage state**, not semantic correctness of product choices. Human acceptance and consistency/convergence review remain separate gates.

## Current-state conflict/drift/closure gaps

Accepted CPS may contain known `CONFLICT` or `DRIFT` because that discrepancy can itself be current truth.

If a goal touches such an area, surface it and ask only the desired future-state decision.

A **Discovery Closure gap** is different. Examples:

- omitted material first-party component;
- unclosed first-party material dependency;
- known public/passive runtime missing observation;
- materially stale/incorrect CPS fact.

These route to:

```text
DISCOVERY_REFRESH_REQUIRED
→ AIDOS-Builder
→ close missing current-state branch
→ accept new CPS
→ Definition consistency check
```

Do not ask the human to invent a product decision as a substitute for objective discovery.

## Consistency gate

Before `ACCEPTED`, check:

- Definition surface progress is `READY_FOR_REVIEW` and validator passes;
- no material development-surface applicability remains unresolved;
- profile defaults have not been mistaken for verified project truth;
- internal Definition contradictions;
- contradictions with accepted Project Baseline/CPS evidence;
- required behaviour without acceptance coverage;
- acceptance checks for behaviour not requested;
- hidden material assumptions;
- non-functional constraints that can invalidate behaviour;
- accidental re-specification of unchanged existing functionality;
- preparation/CPS binding still valid and closure-compatible.

## Reopen

Definition is immutable once accepted except through a new version.

- Desired future requirement contradiction → reopen Definition and durable surface progress/applicability.
- Pre-existing current-product discovery/closure failure → refresh CPS first.
- Launch gate change after scope freeze → explicit Launch Definition reopen/version.

When reopening a Definition, preserve the prior progress/applicability snapshot as lineage; initialize the new version from still-valid surfaces and mark only affected surfaces incomplete/decision-required rather than restarting from chat history.

## Launch Definition / Release Gate

When a product/material release is expected to reach real users, establish a release-scoped Launch Definition before the final development phase where practical.

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

The Launch Definition identifies core launch promise/flows, material security/privacy/data-integrity/compliance conditions, required reliability/compatibility/deployment, launch evidence, deliberate deferred scope, release/audience/environment and human acceptance/version.

After acceptance, new findings are classified as `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`.
