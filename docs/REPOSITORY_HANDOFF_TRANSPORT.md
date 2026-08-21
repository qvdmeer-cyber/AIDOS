# Repository Handoff Transport

## Status

The repository handoff transport is the replacement path for bidirectional ChatGPT Classic content capture.

Its governing rule is:

> Actor work content moves only through the project repository. The desktop bridge may activate an actor session, but it does not read actor responses or treat a chat as workflow state.

AIDOS Core remains authoritative for project state, Definition, scheduling, Human Input, execution, review, recovery and persistence.

## Authority model

```text
AIDOS Core
  publishes one bound ASSIGNMENT
        ↓
project repository/.aidos/HANDOFF.md
        ↓
Thinker or Worker performs only that assignment
        ↓
project repository RESULT
        ↓
AIDOS Core validates/reconciles
        ↓
AIDOS Core selects the next actor
```

Actors never schedule one another directly.

- `CORE → THINKER|WORKER|HUMAN` is an `ASSIGNMENT`.
- `THINKER|WORKER|HUMAN → CORE` is a `RESULT`.
- The next assignment must name the preceding result as its parent.
- A result must name the exact current assignment as its parent.
- Project, Definition, execution, revision and review bindings are copied exactly.

## Canonical handoff

The active handoff is:

```text
.aidos/HANDOFF.md
```

The file contains:

1. one machine-readable JSON metadata block between fixed markers;
2. one human-readable Markdown body;
3. a reference to the exact payload in `.aidos`;
4. a SHA-256 binding for that payload;
5. the exact authorized source references.

The metadata schema is `schemas/repository-handoff.schema.json`.

Important fields include:

```text
handoff_id
project_id
kind
from_actor
to_actor
parent_handoff_id
action
payload_ref
payload_sha256
binding
source_refs
```

Repository-relative path traversal, multiple metadata blocks, stale parent replacement, invalid actor transitions and project mismatches fail closed.

## Thinker transport

### Assignment publication

Core publishes a Definition/reasoning or review assignment to `.aidos/HANDOFF.md`, persists its exact payload and authorized source references, and activates the manually bound project conversation.

The desktop bridge sends only a small wake marker:

```text
AIDOS_HANDOFF_READY
project_id=<exact project id>
handoff_id=<exact handoff id>
handoff_sha256=<exact HANDOFF.md hash>
repository=<exact repository identity>
```

No assignment content is pasted into the chat.

### Custom GPT Action

The private AIDOS Repository Thinker GPT uses three operations:

```text
getAidosProjectHandoff
getAidosAuthorizedSource
submitAidosBoundResult
```

The generated OpenAPI document is written to:

```text
%LOCALAPPDATA%\AIDOS\repository-handoff-host\OPENAPI.json
```

The generated GPT instructions are written to:

```text
%LOCALAPPDATA%\AIDOS\repository-handoff-host\GPT_INSTRUCTIONS.md
```

The Thinker must:

1. fetch the current handoff for the exact project id from the wake marker;
2. verify project id, handoff id and handoff hash exactly;
3. read only exact `source_refs` authorized by that handoff;
4. produce only the required `RUNTIME_ACTOR_RESULT` or `REVIEW_RESPONSE`;
5. submit it with the exact assignment handoff as parent;
6. leave next-actor selection to Core.

The Thinker never places the work product or result JSON in the chat.

### Conversation binding

Each project has one disposable, manually bound, pinned ChatGPT conversation. The default exact title is:

```text
AIDOS :: <PROJECT_ID> :: THINKER
```

The binding stores the conversation title and conversation URL, not a transient window handle. Activation fails closed when the title is missing, ambiguous or no longer resolves to the bound URL.

Trigger delivery is idempotent per `handoff_id`. Failed activation enters bounded backoff and can be reset explicitly.

The Windows keyboard carrier prefers `SendInput`. A live authorized interactive
host may return zero accepted events without a diagnostic that distinguishes an
input-blocked thread from UIPI. In that exact zero-event case only, the carrier
may use the legacy `keybd_event` compatibility path. Because that API has no
acceptance result, Core first replaces the composer with a unique non-payload
sentinel and proves the exact sentinel through the live UI Automation surface.
Only then may it hydrate and prove the real wake marker. Partial `SendInput`
acceptance never falls back: Core issues best-effort key-up cleanup and fails
closed. Submit remains gated by exact payload hydration, a bound submit action
or focused Enter fallback, and post-submit composer-clearance proof.

## Worker transport

The Codex Worker reads the exact repository handoff and execution payload. It is instructed not to commit, push or start another actor.

The existing Worker Git authority guard remains authoritative. Repository lifecycle commits therefore follow this order:

```text
Core writes local Worker ASSIGNMENT handoff
→ no Git commit yet
→ Codex executes
→ Worker writes local RESULT handoff
→ no Git commit yet
→ existing Worker dispatch guard verifies Git HEAD did not change
→ only after PASS, Core commits scoped .aidos lifecycle files
→ Worker source delta remains uncommitted for Thinker review
```

This avoids classifying Core-owned handoff commits as illegal Worker commits.

The finalizer commits only authorized `.aidos` paths. Product/source changes remain in the worktree until an accepted review is integrated by Core.

## Review transport

After a validated Worker result, Core publishes the immutable review package and a Thinker `REVIEW` assignment. The Thinker reads only the bound assignment, manifest and evidence references, then submits one exact `REVIEW_RESPONSE`.

Core validates and consumes that response before publishing the repository `RESULT` handoff. Review outcomes, repair planning, blockers, Human Input and PASS integration remain owned by existing Core mechanisms.

## Local gateway

`AidosRepositoryHandoffGateway.psm1` exposes a loopback-only `HttpListener`:

```text
http://127.0.0.1:47831/
```

Endpoints:

```text
GET  /health
GET  /v1/projects/{projectId}/handoff
GET  /v1/projects/{projectId}/sources?path=<exact source_ref>
POST /v1/projects/{projectId}/results
```

Controls include:

- a generated 256-bit bearer API key;
- fixed-time key comparison;
- project registry binding;
- active runtime-project requirement;
- exact handoff and assignment/review identity validation;
- source allow-list enforcement;
- project/AIDOS authority-root containment;
- request and source size limits;
- UTF-8 text enforcement;
- secret-pattern rejection for authorized sources;
- idempotent result submission;
- `Cache-Control: no-store` responses;
- bridge wake-up after accepted results.

The API key is stored separately from host configuration and restricted to the configured Windows user and `SYSTEM`.

## HTTPS exposure through Tailscale Funnel

A custom GPT Action requires an HTTPS endpoint reachable by OpenAI. The installer can configure Tailscale Funnel to proxy the public HTTPS origin to the loopback gateway.

Default mapping:

```text
https://<machine>.<tailnet>.ts.net
        ↓ Tailscale Funnel/TLS
http://127.0.0.1:47831
```

Supported Funnel HTTPS ports are `443`, `8443` and `10000`. Non-default ports are included in the generated OpenAPI server URL.

The endpoint is publicly reachable on the internet, although its content remains protected by the bearer key and handoff-level validation. The `ts.net` hostname used for HTTPS may be visible in public Certificate Transparency logs. Do not encode confidential project information in the machine or tailnet DNS name.

Official references:

- <https://tailscale.com/kb/1223/funnel>
- <https://tailscale.com/kb/1242/tailscale-serve>
- <https://tailscale.com/kb/1080/cli>

## Windows installation

### Prerequisites

- Windows PowerShell 7 (`pwsh.exe`);
- the unlocked interactive session for the configured AIDOS Windows account;
- local AIDOS, AIDOS-Builder and AIDOS-Contracts repositories;
- the AIDOS project registry;
- ChatGPT Classic installed and signed in;
- Tailscale installed, connected and permitted to use Funnel;
- an elevated PowerShell 7 window for the first URL ACL installation.

The persistent scheduled task itself runs as the configured user with limited privileges and interactive logon type.

### Install

Example for the current WSL repository layout:

```powershell
$entry = "\\wsl.localhost\Ubuntu\home\aidos\repos\AIDOS\bridge\Invoke-AidosRepositoryHandoffHost.ps1"

pwsh -NoProfile -File $entry `
  -Command Install `
  -RegistryRoot "$env:LOCALAPPDATA\AIDOS\project-registry" `
  -BuilderRoot "\\wsl.localhost\Ubuntu\home\aidos\repos\AIDOS-Builder" `
  -ContractsRoot "\\wsl.localhost\Ubuntu\home\aidos\repos\AIDOS-Contracts" `
  -AuthorizedUser "AIDOS\qvdm" `
  -ProcessName "ChatGPT Classic" `
  -RetireClassicTransport
```

`-RetireClassicTransport` is intentionally explicit. Installation fails when the legacy `AIDOS Persistent Local Desktop Agent` task still exists and retirement has not been authorized. Legacy state is preserved.

Use `-SkipFunnel -PublicUrl <https-origin>` only when another HTTPS reverse proxy has already been configured securely.

Use `-RepairUrlAcl` only after confirming that no unrelated service should own the exact loopback URL prefix.

### One-time private GPT setup

The ChatGPT product configuration remains a manual platform step.

1. Create one private custom GPT named, for example, `AIDOS Repository Thinker`.
2. Use a model/configuration that supports custom Actions; do not select Pro mode for this GPT.
3. Copy the generated instructions:

```powershell
pwsh -File $entry -Command ShowInstructions -CopyToClipboard
```

4. Create the Action from the generated OpenAPI JSON:

```powershell
pwsh -File $entry -Command ShowOpenApi -CopyToClipboard
```

5. Configure authentication as API key / Bearer.
6. Copy the generated key:

```powershell
pwsh -File $entry -Command ShowApiKey -CopyToClipboard
```

7. Keep the GPT private.

Official OpenAI references:

- <https://help.openai.com/en/articles/8554397-creating-a-gpt>
- <https://platform.openai.com/docs/actions/introduction>
- <https://platform.openai.com/docs/actions/authentication>

### Bind one project conversation

For every project:

1. open the private AIDOS Repository Thinker GPT;
2. create a new conversation;
3. rename it exactly to `AIDOS :: <PROJECT_ID> :: THINKER`;
4. pin it;
5. leave that conversation active;
6. run:

```powershell
pwsh -File $entry -Command BindThinker -ProjectId <PROJECT_ID>
```

A conversation may be discarded and rebound without losing AIDOS state because the chat is not durable truth.

## Operations

The configured GPT Action also exposes authenticated project controls. In the exact bound conversation, whole-message `START`/`CONTINUE`/`BEGIN`/`GA VERDER` commands submit Core `RESUME`; whole-message `STOP`/`STOPPEN`/`PAUZE` commands submit Core `PAUSE`. These commands only carry intent. Core persists and validates the control, returns an exact acknowledgement, and remains responsible for actor selection. The gateway must remain running while a project is paused so chat `START` stays reachable.

```powershell
# Host, task, gateway, bridge and Funnel status
pwsh -File $entry -Command Status

# One synchronous diagnostic tick
pwsh -File $entry -Command Tick

# Stop the running host
pwsh -File $entry -Command Stop

# Remove a project chat binding
pwsh -File $entry -Command UnbindThinker -ProjectId <PROJECT_ID>

# Permit one explicit retrigger after an investigated failure
pwsh -File $entry -Command ResetThinkerTrigger -ProjectId <PROJECT_ID> -HandoffId <HANDOFF_ID>

# Rotate the gateway key; then update the private GPT Action credential
pwsh -File $entry -Command RotateKey

# Inspect Funnel state
pwsh -File $entry -Command FunnelStatus

# Uninstall task and Funnel while preserving local evidence/configuration
pwsh -File $entry -Command Uninstall
```

Use `-RemoveState` only when local bridge/gateway/host state should also be deleted. Use `-KeepFunnel` only when the HTTPS endpoint remains intentionally owned by another configuration.

## Failure and recovery behavior

- Missing or ambiguous ChatGPT conversation: no send; bounded retry backoff.
- Unbound project: no Thinker trigger.
- Stale handoff parent: result rejected.
- Hash/binding mismatch: result rejected.
- Unauthorized source: source read rejected.
- Codex Git commit: existing guard forces `RECOVERY_REQUIRED`; Core does not finalize the Worker handoff commit.
- Gateway or bridge child exit: supervisor records `ERROR` and the scheduled task restart policy applies.
- Duplicate result submission for the same parent: returned as `ALREADY_ACCEPTED`.
- Lost chat/session: create and bind a replacement; no workflow reconstruction is required.

## Test coverage

The repository handoff validation workflow covers:

- handoff contract and transition rules;
- scoped persistence with a dirty Worker worktree;
- OpenAPI generation;
- installation/Funnel/URL ACL configuration models;
- Worker assignment/result publication;
- Worker runtime integration through the existing Git authority guard;
- authenticated gateway routing and result binding;
- manual project conversation binding, activation, idempotency and backoff;
- unified preparation/runtime bridge behavior.

The Windows installer additionally requires a live machine smoke test because GitHub-hosted CI cannot configure the operator's ChatGPT account, private GPT Action, Tailscale tailnet permissions or persistent interactive desktop session.
