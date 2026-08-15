# Review protocol

## Review objective

Determine whether the exact accepted Definition has been delivered with adequate evidence and no unapproved behaviour expansion.

For `EXISTING_PROJECT`, review also verifies the exact closure-compatible Current Product State binding and distinguishes:

- desired product/Definition contradiction;
- ordinary expected product change caused by execution;
- **pre-existing Discovery Closure failure** in the bound CPS.

When a frozen Launch Definition applies, review additionally evaluates release readiness without allowing improvement ideas to expand frozen scope.

## Review order

1. Binding integrity: project mode, Project Baseline, CPS ID/commit + CPS/discovery contract versions, Definition, execution, revision, branch/head, review ID.
2. Verify existing-project discovery state was accepted/current at dispatch.
3. Launch Definition/release binding where applicable.
4. Terminal legitimacy.
5. Acceptance check and validator/evidence integrity.
6. Definition convergence: delivered desired delta versus accepted intent.
7. Existing-product current-state reconciliation:
   - did this execution itself cause the changed state?;
   - or did evidence expose an omitted material first-party component/dependency branch?;
   - or did evidence expose missing reasonably observable runtime?
   - or was the bound CPS otherwise materially stale/wrong before execution?
8. Launch Definition convergence where applicable.
9. Release-finding classification where applicable.
10. Scope/authority compliance.
11. Cleanup/final-state requirements.
12. Learning candidates.

## Outcomes

### `ACCEPTED`

Outcome is complete. Record decision durably and consume/clean ephemeral review transport.

Expected state change caused by the accepted execution does not by itself mean the pre-execution CPS was invalid.

### `DISCOVERY_REFRESH_REQUIRED`

Use for `EXISTING_PROJECT` when objective evidence shows the accepted pre-execution current-state preparation did not satisfy reliable product closure, including:

- an omitted `FIRST_PARTY_MATERIAL` component;
- an unclosed material first-party dependency branch;
- known reasonably observable public/passive runtime that was absent or `NOT_OBSERVED`;
- material source/runtime reference that was unresolved;
- other material inaccuracy in the pre-execution CPS.

Route:

```text
AIDOS review
→ preserve precise evidence
→ DISCOVERY_REFRESH_REQUIRED
→ AIDOS-Builder
→ preserve old accepted CPS/evidence lineage
→ close only missing branches/runtime observations
→ deterministic closure validation
→ accept new CPS
→ Definition consistency check
```

Do **not** ask the human for a product decision merely to compensate for missing objective discovery evidence.

Do not use this outcome merely because execution changed the product as intended.

### `REPAIR`

Technical correction remains inside accepted Definition, current preparation binding, authority and frozen release scope where applicable.

### `CONTRADICTION`

Use when the desired future product behaviour/requirement itself conflicts with project truth and a human product decision is required.

Do not use `CONTRADICTION` for a missing current-product discovery branch; refresh discovery first.

### `GATE / BLOCKED`

Human authority/reasoning is required before safe continuation.

### `RELEASE_READY`

Use when all accepted Launch Definition criteria PASS, no unresolved `LAUNCH_BLOCKER` remains and launch evidence is complete. This is the default forward state; do not solicit another round of polish/features.

## Authority distinction

Discovery Authority and Execution Authority are independent. The fact that AIDOS-Builder may passively inspect public runtime or follow a first-party source read-only does not authorize Worker/Execution to mutate that runtime/source.

## Release-finding classification

After release-scope freeze, new material findings are exactly one of:

- `LAUNCH_BLOCKER`;
- `POST_LAUNCH`;
- `EVIDENCE_REQUIRED`.

"This can be better", subjective incompleteness or a new feature idea is not blocker evidence by itself. Preserve useful `POST_LAUNCH` findings in the project-local backlog.

## Explicit delay after readiness

Delay after `RELEASE_READY` requires explicit Launch Definition/release-scope reopen with reason, changed criterion/scope, consequence where knowable and renewed acceptance.

## No review-by-volume

Prefer the smallest complete proof. Code already available at an exact commit should not be redundantly packaged.
