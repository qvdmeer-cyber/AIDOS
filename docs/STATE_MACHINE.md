# State machine

AIDOS uses explicit states so neither GPT nor Codex can infer permission to continue merely from conversation context.

## External preparation gate

Preparation state is owned by AIDOS-Builder/AIDOS-Contracts but is a hard prerequisite for private AIDOS runtime:

```text
NEW_PROJECT
PROJECT_BASELINE_ACCEPTED
→ AIDOS runtime eligible

EXISTING_PROJECT
PROJECT_BASELINE_ACCEPTED
→ CURRENT_PRODUCT_STATE_REQUIRED
→ CURRENT_PRODUCT_STATE_ACCEPTED
→ AIDOS runtime eligible
```

Private AIDOS must not compensate for missing Existing Project Discovery by allowing Definition to reconstruct the current product informally.

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

If current evidence shows the bound Current Product State is materially stale/wrong:

```text
ACCEPTED / GPT_REVIEWING
→ DISCOVERY_REFRESH_REQUIRED
→ AIDOS-Builder refresh
→ CURRENT_PRODUCT_STATE_ACCEPTED (new snapshot/version)
→ Definition consistency check
→ resume or REOPENED if desired delta is affected
```

## Launch Definition states

A product/material release may additionally have a release-scoped Launch Definition:

```text
LAUNCH_DISCOVERY
→ LAUNCH_PROPOSED
→ LAUNCH_USER_REVIEW
→ LAUNCH_ACCEPTED
→ RELEASE_SCOPE_FROZEN
```

After freeze, new findings do not implicitly change the release. They are classified:

```text
LAUNCH_BLOCKER
POST_LAUNCH
EVIDENCE_REQUIRED
```

`POST_LAUNCH` does not leave the frozen release state. `EVIDENCE_REQUIRED` requests bounded evidence, not automatic scope expansion.

A proven blocker or deliberate human delay may explicitly reopen the release gate:

```text
RELEASE_SCOPE_FROZEN / RELEASE_READY
→ LAUNCH_REOPEN_REQUESTED
→ LAUNCH_REOPENED
→ LAUNCH_USER_REVIEW
→ LAUNCH_ACCEPTED
→ RELEASE_SCOPE_FROZEN
```

The prior Launch Definition version remains durable lineage.

## Project/execution states

```text
IDLE
→ TASK_READY
→ CODEX_RUNNING
→ TERMINAL_PENDING
→ REVIEW_READY
→ GPT_REVIEWING

GPT_REVIEWING
├─ ACCEPTED                   → IDLE / next accepted goal
├─ REPAIR                     → TASK_READY (same goal, revised execution)
├─ CONTRADICTION              → WAITING_DEFINITION
├─ DISCOVERY_REFRESH_REQUIRED → external AIDOS-Builder discovery refresh
├─ GATE                       → WAITING_USER
├─ BLOCKED                    → WAITING_USER
└─ RELEASE_READY              → release lifecycle / genuine release authority gate
```

When a frozen Launch Definition exists, ordinary accepted goals within that release do not authorize extra release scope.

## Release-ready invariant

When all accepted Launch Definition criteria are PASS and no unresolved `LAUNCH_BLOCKER` remains:

```text
RELEASE_READY
```

is the default forward state.

AIDOS must not transition from `RELEASE_READY` back to feature discovery merely because a new improvement is imaginable. Additional improvement is routed to `POST_LAUNCH` unless an explicit Launch Definition reopen is accepted.

## Additional infrastructure states

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

`DISCOVERY_REFRESH_REQUIRED` and `RELEASE_READY` are Worker/review states, not Execution Agent self-declared terminal results.

## Success stop

Once acceptance and required evidence are complete, Execution Agent stops. It never starts a new goal because the roadmap makes it obvious.

Only Worker may dispatch another already-accepted goal; only the human/Definition Agent may accept new product intent or reopen frozen release scope.

## Fail-closed transitions

A transition is rejected when project, project mode, preparation binding, definition version, execution ID/revision, root, branch or required commit binding does not match current canonical state.

For `EXISTING_PROJECT`, the accepted Current Product State ID/commit is part of preparation binding. For release-scoped work, Launch Definition/release identity must also match once runtime contracts implement that binding.

See `protocols/LAUNCH_PROTOCOL.md`.
