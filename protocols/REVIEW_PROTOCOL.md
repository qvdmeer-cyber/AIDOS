# Review protocol

## Review objective

Determine whether the exact accepted Definition has been delivered with adequate evidence and no unapproved behaviour expansion.

When a frozen Launch Definition applies, review must also determine whether the release gate is satisfied **without allowing improvement ideas to silently expand release scope**.

## Review order

1. Binding integrity: project, Definition, execution, revision, branch/head, review ID.
2. Launch Definition/release binding where applicable.
3. Terminal legitimacy.
4. Acceptance check results.
5. Required validator/evidence integrity.
6. Definition convergence: delivered intent versus accepted intent.
7. Launch Definition convergence where applicable.
8. Classification of new release findings: `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`.
9. Scope/authority compliance.
10. Cleanup/final-state requirements.
11. Learning candidates.

## Outcomes

### ACCEPTED

Outcome is complete. Record review decision durably. Mark ephemeral review transport `REVIEW_CONSUMED`; bridge then cleans it.

For work inside a frozen release, an accepted execution does not by itself reopen release scope.

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

A material product assumption/requirement conflicts with discovered project truth. Stop implementation decision-making and reopen Definition with the human.

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
