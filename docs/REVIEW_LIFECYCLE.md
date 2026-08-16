# Review lifecycle

Review artefacts are **temporary transport evidence**, not durable project documentation.

## Durable content

The project branch keeps durable items such as:

- exact code commit;
- terminal handoff/summary;
- validator receipts that are themselves canonical project evidence;
- execution/review state and event records.
- review record (`.aidos/reviews/<review_id>/REVIEW.json`);
- consume acknowledgement and decision record;
- package manifest hash and evidence refs.

## Ephemeral content

Large/local-only evidence that GPT cannot otherwise inspect may be published through a dedicated temporary review ref/branch bound to one `review_id`.

For the local bridge implementation the first transport carrier is a secret-free ephemeral package directory:

```text
.aidos/runtime/reviews/<review_id>/
├─ MANIFEST.json
└─ ACK.json
```

The durable review record binds the exact project/definition/execution/revision identity and keeps the package locator as a historical reference only.

Example conceptual ref:

```text
ai-review/<project>/<execution>/<revision>/<review-id>
```

A normal deletion commit on the durable development branch is not sufficient cleanup because Git history retains the bytes.

## Lifecycle

```text
Codex terminal state
→ push code/checkpoint
→ create fresh ephemeral review package
→ publish manifest + minimum missing evidence
→ REVIEW_READY
→ publish review transport
→ GPT_REVIEWING
→ Worker consumes exact review_id/manifest
→ review decision persisted durably
→ consume acknowledged durably
→ REVIEW_CONSUMED
→ local bridge deletes ephemeral package
→ CLEANUP_CONFIRMED
```

## Safety rules

- Review artefacts must be secret-free and privacy-safe even though they are temporary.
- Never reuse an old review package/ref for a new terminal claim.
- Review manifest binds project, Definition version, execution, revision, branch/head and evidence hashes.
- Durable review record must remain sufficient canonical evidence after the ephemeral package is cleaned.
- Cleanup occurs only after Worker has durably recorded `REVIEW_CONSUMED`.
- Failure to clean does not erase the review result but raises cleanup state requiring bridge attention before uncontrolled accumulation continues.
