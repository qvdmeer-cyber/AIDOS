# Session rotation

Chats/sessions are caches of reasoning/execution context, not canonical AIDOS, project or workstream state.

## Actor-session principle

AIDOS activates temporary actors against exact durable bindings. Replacing a GPT/Codex session must not change project/workstream identity, Definition/execution bindings, Human Input Requests, blockers or control state.

```text
AIDOS durable state
→ activate temporary actor session
→ actor emits durable event/result
→ session may be discarded
```

A replacement session bootstraps from canonical AIDOS/project/workstream sources, not from implicit predecessor memory.

## Codex / Worker-role session rotation

Keep an existing execution session while useful. Start a new one when one or more apply:

- a materially new goal/workstream begins and old history has little value;
- repeated problem/context loops suggest stale context;
- the session repeatedly applies stale/wrong instructions;
- project/workstream/root binding changes;
- material architecture/runtime context makes old assumptions harmful;
- AIDOS validates a rotation request after review;
- future telemetry demonstrates a useful threshold.

Do not rotate merely because a session is old.

## GPT / Thinker-role session rotation

Definition/reasoning/review chats are disposable too. Rotate when stale project/workstream state is repeatedly used, accepted decisions are reopened without evidence, review becomes contradictory, protocol is not followed, historical context causes confusion or the human/AIDOS requests a clean context.

A project may have temporary project-level and workstream-level Thinker sessions. Their reasoning scope is bound by workstream ownership/shared contracts and does not create a separate source of truth.

### ROTATE versus RESET

`ROTATE` — healthy context replaced proactively; canonical durable state bootstraps the replacement.

`RESET` — predecessor context is considered unreliable. Bootstrap only from canonical repository/AIDOS state, events, Human Input Requests and machine evidence; do not use a prose summary produced by the unreliable predecessor as authority.

## Waiting human input

A Human Input Request survives all session rotation. Any authorized replacement channel/session may display and resolve the same durable request. A chat must never create a semantically new decision request merely because the original asking session disappeared.

## Measured optimization

V1 records usage/context metrics but avoids aggressive automatic token/time thresholds. Rotation parameters should be tuned from allowance consumption, repair rates, stale-context failures and workstream outcomes.
