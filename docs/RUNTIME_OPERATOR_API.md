# Runtime Observability & Operator API

Status: **CORE FOUNDATION IMPLEMENTED**  
Interface UI: **not implemented here**

This layer is the machine-readable boundary between AIDOS Core/runtime and future external clients such as the separate `AIDOS-interface` project.

A client observes projections and submits intents. It does not become source of truth and does not directly start/kill Codex, automate ChatGPT, mutate project workflow files, rewrite state, or decide Definition/review outcomes.

## Entry point

Windows/Linux PowerShell 7:

```powershell
./bridge/Invoke-AidosOperator.ps1 -Command Snapshot -ProjectRoot <project-root>
./bridge/Invoke-AidosOperator.ps1 -Command Status -ProjectRoot <project-root>
./bridge/Invoke-AidosOperator.ps1 -Command Control -ProjectRoot <project-root> -ControlCommand PAUSE -RequestedBy <identity>
```

For a Windows host snapshot, pass the persistent-agent state root explicitly:

```powershell
./bridge/Invoke-AidosOperator.ps1 `
  -Command Snapshot `
  -ProjectRoot <project-root> `
  -HostAgentStateRoot "$env:LOCALAPPDATA\AIDOS\host-agent"
```

The CLI is intentionally transport-neutral. A future authenticated HTTP/WebSocket service may wrap these functions without changing project truth or control semantics.

## Observability

`Status` emits `schemas/runtime-status.schema.json`.

The current projection exposes:

- project identity and canonical workflow state;
- recovery-required flag;
- aggregate open blocker count from persisted workstreams;
- open Human Input Request IDs;
- project progress-estimate reference when available;
- persisted workstreams;
- current workstream actor role;
- workstream blocker count;
- workstream Human Input Request IDs;
- workstream progress-estimate references.

`Snapshot` emits `schemas/operator-snapshot.schema.json` and adds:

- current operator control mode;
- optional persistent Windows host-agent heartbeat/status;
- recent durable project events.

Host-agent operational status is deliberately separate from project workflow state.

## Control intents

Every request uses the existing `schemas/control-intent.schema.json` envelope and is persisted under:

```text
.aidos/control/intents/<control_id>.json
```

The record lifecycle is durable:

```text
RECEIVED
→ ACCEPTED
→ APPLIED or REJECTED
```

A control request is never treated as a direct project-state mutation.

### Implemented commands

`QUERY_STATUS`
: Produces the current runtime projection and records it as the applied result.

`PAUSE`
: Persists operator mode `PAUSED`. The Persistent Local Desktop Agent checks this mode before review reconciliation/desktop Worker activation and returns `PAUSED / OPERATOR_CONTROL` instead of starting new Worker work. Already-running bounded work is not killed.

`SAFE_STOP`
: Persists operator mode `SAFE_STOPPED`. The persistent Worker loop performs no new review/desktop activation. This is a safe-boundary stop, not process-tree termination.

`RUN` / `RESUME`
: Return operator mode to `RUNNING`. They fail closed while canonical project state is `RECOVERY_REQUIRED`.

### Explicitly not fabricated

`SUBMIT_HUMAN_INPUT`
: The generic operator endpoint currently rejects this command. Exact Human Input Request binding/resolution remains owned by the canonical Human Input processor.

`REQUEST_RECOVERY`
: The generic operator endpoint currently rejects this command. Recovery remains an explicit AIDOS Core reconciliation action until its dedicated processor is integrated.

Rejected commands remain durable intents with the rejection reason. The API does not pretend an unsupported action was applied.

## Control state

Desired operator mode is stored separately from canonical workflow state:

```text
.aidos/runtime/operator-control.json
```

Modes:

- `RUNNING`
- `PAUSED`
- `SAFE_STOPPED`

This state gates new runtime activation; it does not replace `.aidos/STATE.json`.

## Progress / ETA

The operator projection exposes a `progress_estimate_ref` when a persisted estimate exists under the project progress surface. The estimate itself follows `schemas/progress-estimate.schema.json`, including:

- progress fraction;
- weighted components;
- remaining weight;
- validation/integration state;
- ETA confidence;
- estimated/lower/upper remaining seconds;
- assumptions;
- eventual estimated-versus-actual outcome.

The runtime does not invent an ETA when no evidence-backed progress estimate exists.

## Security / authority boundary

The operator boundary preserves these invariants:

1. client visibility does not grant mutation authority;
2. every mutating request becomes a durable control intent first;
3. invalid or unsupported intents fail closed and remain auditable;
4. `PAUSE`/`SAFE_STOP` do not kill bounded work abruptly;
5. canonical AIDOS state and review/Definition decisions remain authoritative;
6. external authentication/authorization belongs to the future network transport, not to the transport-neutral core module;
7. AIDOS remains functional when no Interface exists or the Interface is offline.

## Current acceptance

Portable Core CI covers:

- PowerShell syntax parsing;
- JSON contract parsing;
- runtime projection generation;
- blockers/Human Input/workstream/progress-reference projection;
- recent event projection;
- durable `PAUSE`, `RESUME`, `SAFE_STOP`, and `QUERY_STATUS` intent handling;
- fail-closed unsupported commands;
- fail-closed `RUN` during `RECOVERY_REQUIRED`.

The Persistent Local Desktop Agent additionally consumes operator mode before starting new Worker review/desktop activity.

## Next consumer

The first intended external consumer is the separate `qvdmeer-cyber/AIDOS-interface` project. That project should consume this boundary rather than reaching into `.aidos` project files or Windows process/session internals directly.
