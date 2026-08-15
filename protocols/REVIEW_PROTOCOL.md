# Review protocol

## Review objective

Determine whether the exact accepted Definition has been delivered with adequate evidence and no unapproved behaviour expansion.

## Review order

1. Binding integrity: project, Definition, execution, revision, branch/head, review ID.
2. Terminal legitimacy.
3. Acceptance check results.
4. Required validator/evidence integrity.
5. Definition convergence: delivered intent versus accepted intent.
6. Scope/authority compliance.
7. Cleanup/final-state requirements.
8. Learning candidates.

## Outcomes

### ACCEPTED

Outcome is complete. Record review decision durably. Mark ephemeral review transport `REVIEW_CONSUMED`; bridge then cleans it.

### REPAIR

Technical correction remains entirely inside accepted Definition/authority. Increment execution revision as required and dispatch back to execution.

### CONTRADICTION

A material product assumption/requirement conflicts with discovered project truth. Stop implementation decision-making and reopen Definition with the human.

### GATE / BLOCKED

Human authority or reasoning is required before safe continuation.

## No review-by-volume

Large evidence packages are not intrinsically better. Prefer the smallest complete proof. Source code already present at an exact commit should not be redundantly zipped for GPT.
