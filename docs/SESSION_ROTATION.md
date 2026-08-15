# Session rotation

Chats/sessions are caches of reasoning context, not canonical project state.

## Codex session rotation

Keep the existing session by default while it remains useful.

Start a new Codex session when one or more apply:

- a materially new development goal begins and old history has little execution value;
- Codex is stuck in a repeated problem/context loop;
- the session is polluted and repeatedly applies stale/wrong instructions;
- project or official root changes;
- a material architecture/runtime context break makes old assumptions actively harmful;
- Worker explicitly requests `ROTATE_SESSION` after review;
- future telemetry demonstrates a clear context/allowance threshold.

Do not rotate merely because a session is old.

## GPT session rotation

Definition and Worker chats must also be disposable.

Rotate when:

- stale execution/project state is repeatedly used;
- decisions already accepted are repeatedly reopened without new evidence;
- reviews become contradictory without changed evidence;
- agent protocol is no longer followed reliably;
- responses become materially confused by historical context;
- the human requests a clean session.

### ROTATE versus RESET

`ROTATE` — healthy session replaced proactively; current canonical repository state bootstraps the replacement.

`RESET` — current context is considered unreliable. The replacement must bootstrap only from canonical project/AIDOS sources and machine evidence, not from a prose summary produced by the confused predecessor.

## Measured optimization

V1 records usage/context metrics but intentionally avoids aggressive automatic token/time thresholds. Rotation parameters should be tuned from real allowance consumption and observed failure patterns.
