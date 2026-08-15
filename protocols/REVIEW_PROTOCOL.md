# Review protocol

## Review objective

Determine whether the exact accepted Definition has been delivered with adequate evidence and no unapproved behaviour expansion.

For `EXISTING_PROJECT`, review also verifies that execution was based on the bound accepted Current Product State and distinguishes **goal/Definition contradiction** from **stale or incorrect pre-execution current-state discovery**.

When a frozen Launch Definition applies, review must additionally determine whether the release gate is satisfied **without allowing improvement ideas to silently expand release scope**.

## Review order

1. Binding integrity: project mode, Project Baseline, Current Product State where applicable, Definition, execution, revision, branch/head, review ID.
2. Launch Definition/release binding where applicable.
3. Terminal legitimacy.
4. Acceptance check results.
5. Required validator/evidence integrity.
6. Definition convergence: delivered desired delta versus accepted intent.
7. For existing products, current-state reconciliation: did execution reveal that the bound CPS was materially stale/wrong before execution, versus ordinary state change caused by this execution?
8. Launch Definition convergence where applicable.
9. Classification of new release findings: `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`.
10. Scope/authority compliance.
11. Cleanup/final-state requirements.
12. Learning candidates.

## Outcomes

### ACCEPTED

Outcome is complete. Record review decision durably. Mark ephemeral review transport `REVIEW_CONSUMED`; bridge then cleans it.

For work inside a frozen release, an accepted execution does not by itself reopen release scope.

### DISCOVERY_REFRESH_REQUIRED

Use only for `EXISTING_PROJECT` when new evidence shows the accepted pre-execution Current Product State was materially stale, incomplete or incorrect in a way that affects reliable future reasoning.

This is **not** a request for the Worker or Definition Agent to reverse-engineer the project themselves.

Route:

```text
AIDOS review
→ preserve new evidence
→ AIDOS-Builder Existing Project Discovery refresh
→ deterministic CPS validation
→ human acceptance of new CPS snapshot
→ Definition consistency check
→ resume existing Definition or reopen only if the desired delta is affected
```

Do not use this outcome merely because execution changed the product as intended. Expected post-execution change means the old CPS was a valid pre-execution snapshot, not stale discovery.

### RELEASE_READY

Use when a Launch Definition applies and:

- all accepted launch criteria are PASS;
- no unresolved `LAUNCH_BLOCKER` remains;
- required launch evidence is complete.

This is the default forward state. Do not ask whether the owner wants additional polish/features before proceeding.

The next action is the already-authorized release lifecycle or the next genuine release authority gate.

### REPAIR

Technical correction remains entirely inside accepted Definition/authority and frozen release scope where applicable. Increment execution revision as required and dispatch back to execution.

### CONTRADICTION

Use when a material **desired product assumption/requirement** conflicts with discovered project truth and the future behavior requires a human product decision.

Do not use `CONTRADICTION` merely because the previously accepted CPS was inaccurate; use `DISCOVERY_REFRESH_REQUIRED` first in that case.

If the contradiction invalidates a frozen release criterion, preserve Launch Definition lineage and reopen it explicitly rather than silently changing the release gate.

### GATE / BLOCKED

Human authority or reasoning is required before safe continuation.

## Release-finding classification

After Launch Definition acceptance, every new material release-related finding must be classified:

- `LAUNCH_BLOCKER` — objective violation of the core promise/accepted launch criterion or comparable material security/privacy/data-loss/compliance risk;
- `POST_LAUNCH` — useful improvement that does not justify delay;
- `EVIDENCE_REQUIRED` — plausible concern whose release-criticality is not yet evidenced.

Statements such as "this can be better", "this feels unfinished" or a newly imagined feature do not constitute blocker evidence.

Useful `POST_LAUNCH` findings must be preserved in the project-local backlog, not lost.

## Explicit delay after readiness

If the human elects to delay once `RELEASE_READY` is reached, that is a deliberate governance exception:

- reopen/version Launch Definition or release scope explicitly;
- record the reason;
- record the changed criterion/scope;
- record timing/risk consequence where knowable;
- obtain renewed human acceptance.

## No review-by-volume

Large evidence packages are not intrinsically better. Prefer the smallest complete proof. Source code already present at an exact commit should not be redundantly zipped for GPT.

See `protocols/LAUNCH_PROTOCOL.md`.
