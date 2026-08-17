# Human input / interruption protocol

## Purpose

AIDOS should run independently while routing genuine human decisions through durable, channel-independent state.

Human input is not owned by a particular GPT chat. The canonical artifact is a **Human Input Request** conforming to `schemas/human-input-request.schema.json`.

## Human Input Request

When human input is required, persist a request containing at least:

- `project_id` and optional `workstream_id`;
- concise context/evidence summary;
- one concrete decision/question;
- allowed options where useful;
- exact Definition/execution/revision/review binding where applicable;
- request type/reason;
- current safe waiting state;
- actor role to resume after resolution;
- status `WAITING` / `RESOLVED` / terminal replacement status;
- human response and response event/evidence.

Recommended project-local location:

```text
.aidos/human-input/<request_id>.json
```

## Control flow

Actors publish the request; they do not own the resume action.

```text
actor reaches genuine boundary
→ durable Human Input Request WAITING
→ AIDOS exposes request through available channel
→ human responds
→ AIDOS validates identity/binding/response
→ request RESOLVED + event
→ AIDOS determines next valid actor
```

This permits a mobile client, replacement GPT chat, CLI or future Interface to resolve the same request without changing workflow semantics.

## Typical reasons

Human Input Requests include product/Definition decisions, authority expansion, risk acceptance, recovery choice, discovery authority grants, release decisions and material clarification that objective evidence cannot resolve.

Ordinary technical repair is not a human-input reason while safe bounded technical autonomy remains.

## Product contradiction

For a Definition contradiction, persist the request against the exact Definition lineage. The Definition/Thinker role may formulate the decision, but AIDOS resumes only after the response is durably validated and any revised Definition is accepted.

## Waiting state

The currently proven top-level runtime uses `WAITING_USER`. Human Input Request `WAITING` is the first-class reason/binding behind that wait. A future state-model version may expose a more explicit `WAITING_HUMAN_INPUT` projection, but existing runtime semantics are not renamed prematurely.

## Mobile/session continuity

Canonical project/workstream/request state, not device-local chat history, is the basis for resuming. A new or rotated GPT session reads the same unresolved request and bound Definition/execution state.

## Supervised runner

If the runner is locked under `SUPERVISED`, an already-running bounded Codex execution may finish safely, but the next interactive actor must not start. Pending review/Human Input Request remains durable until policy permits activation.
