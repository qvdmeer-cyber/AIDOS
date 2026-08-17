# Definition progress / convergence

## Purpose

Definition elicitation must not depend on a GPT chat remembering which concerns have already been resolved.

Each Definition version therefore maintains a durable per-surface progress projection in the project repository:

```text
.aidos/definitions/<definition_id>/v<version>/PROGRESS.json
```

The fixed surface list is owned by private AIDOS Core in `catalog/definition-surfaces.catalog.json`.

## Surfaces

The catalog currently tracks 13 concerns:

1. goal and scope;
2. current state and desired delta;
3. functional behaviour;
4. actors and permissions;
5. main flows;
6. edge/error states;
7. data and lifecycle;
8. security and privacy;
9. compatibility/performance/runtime;
10. observability and recovery;
11. acceptance coverage;
12. out of scope;
13. unresolved assumptions.

A surface is one of `COMPLETE`, `NOT_APPLICABLE`, `INCOMPLETE`, `DECISION_REQUIRED` or `BLOCKED`.

Only `COMPLETE` and justified `NOT_APPLICABLE` count toward Definition coverage completion.

## Human-decision transaction

After each human Definition decision:

```text
persist decision
→ update affected surfaces
→ recalculate totals/next surface
→ validate PROGRESS.json
→ display every surface to the human
→ ask the next single question
```

If persistence or progress validation fails, the Definition Agent must not proceed to the next question.

## Visible progress

The Definition Agent always renders the progress from the newly persisted object. Example:

```text
Definition v3 · 9/13 complete
✓ Goal and scope
✓ Current state and desired delta
✓ Functional behaviour
△ Actors and permissions · decision required
✓ Main flows
○ Edge and error states · incomplete
— Data and lifecycle · not applicable
✓ Security and privacy
✓ Compatibility, performance and runtime
✓ Observability and recovery
○ Acceptance coverage · incomplete
✓ Out of scope
○ Unresolved assumptions · incomplete
Next surface: actors_permissions
```

This repetition is intentional. It provides a human-visible convergence check and makes omissions visible before acceptance.

## Chat rotation/reset

Chats are disposable.

A new Definition chat resumes from:

```text
accepted preparation state
+ durable Definition state/decisions
+ PROGRESS.json
```

It does not inherit completeness from a prose summary of the previous chat.

## Review gate

Before Definition enters user review, `Test-AidosDefinitionProgress.ps1 -RequireReady` (or equivalent implementation) must pass.

This proves coverage bookkeeping is complete. It does not prove that the chosen product decisions are semantically correct; the consistency gate and explicit human acceptance remain separate controls.

## Reopen

When an accepted Definition is reopened, preserve the prior version/progress as lineage. A new version inherits still-valid completed surfaces and reopens only surfaces affected by the contradiction or changed decision.
