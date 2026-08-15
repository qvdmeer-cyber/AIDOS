# State machine

AIDOS uses explicit states so neither GPT nor Codex can infer permission to continue merely from conversation context.

## Definition states

```text
DISCOVERY
→ OPEN_QUESTIONS
→ PROPOSED
→ USER_REVIEW
→ ACCEPTED

ACCEPTED
→ CONTRADICTION_FOUND
→ REOPENED
→ OPEN_QUESTIONS
→ ...
```

Only `ACCEPTED` may authorize creation of a new execution for that Definition version.

## Project/execution states

```text
IDLE
→ TASK_READY
→ CODEX_RUNNING
→ TERMINAL_PENDING
→ REVIEW_READY
→ GPT_REVIEWING

GPT_REVIEWING
├─ ACCEPTED      → IDLE / next accepted goal
├─ REPAIR        → TASK_READY (same goal, revised execution)
├─ CONTRADICTION → WAITING_DEFINITION
├─ GATE          → WAITING_USER
└─ BLOCKED       → WAITING_USER
```

Additional infrastructure states:

- `QUEUED` — task valid but waiting for a local execution slot;
- `WAITING_INTERACTIVE_SESSION` — review/work is ready but supervised policy blocks desktop GPT activation;
- `CONTEXT_ROTATION_REQUIRED` — current GPT/Codex session must not be resumed;
- `RECOVERY_REQUIRED` — state cannot safely advance until reconciliation completes.

## Execution terminal outcomes

Execution Agent may terminate only as:

- `TER_REVIEW` — accepted outcome appears complete and evidence is ready;
- `CONTROLLED_GATE` — new material authority/decision is required;
- `BLOCKER` — safe technical autonomy is exhausted;
- `RUNTIME_STOP` — agent/runtime itself cannot continue;
- `REQUIREMENT_CONTRADICTION` — project evidence conflicts materially with the accepted Definition.

Ordinary build/test/runtime failures are not terminal while safe useful technical steps remain.

## Success stop

Once acceptance and required evidence are complete, Execution Agent stops. It never starts a new goal because the roadmap makes it obvious.

Only Worker may dispatch another already-accepted goal; only the human/Definition Agent may accept new product intent.

## Fail-closed transitions

A transition is rejected when project, definition version, execution ID/revision, root, branch or required commit binding does not match current canonical state.
