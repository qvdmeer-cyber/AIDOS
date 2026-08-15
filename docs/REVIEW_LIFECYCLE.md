# Review lifecycle

Review artefacts are **temporary transport evidence**, not durable project documentation.

## Durable content

The project branch keeps durable items such as:

- exact code commit;
- terminal handoff/summary;
- validator receipts that are themselves canonical project evidence;
- execution/review state and event records.

## Ephemeral content

Large/local-only evidence that GPT cannot otherwise inspect may be published through a dedicated temporary review ref/branch bound to one `review_id`.

Example conceptual ref:

```text
ai-review/<project>/<execution>/<revision>/<review-id>
```

A normal deletion commit on the durable development branch is not sufficient cleanup because Git history retains the bytes.

## Lifecycle

```text
Codex terminal state
→ push code/checkpoint
→ create fresh ephemeral review ref only if needed
→ publish manifest + minimum missing evidence
→ REVIEW_READY
→ Worker consumes exact review_id/commit
→ review decision persisted durably
→ REVIEW_CONSUMED
→ local bridge deletes remote ephemeral ref
→ delete local package/temp evidence
→ CLEANUP_CONFIRMED
```

## Safety rules

- Review artefacts must be secret-free and privacy-safe even though they are temporary.
- Never reuse an old review package/ref for a new terminal claim.
- Review manifest binds project, Definition version, execution, revision, branch/head and evidence hashes.
- Cleanup occurs only after Worker has durably recorded `REVIEW_CONSUMED`.
- Failure to clean does not erase the review result but raises cleanup state requiring bridge attention before uncontrolled accumulation continues.
