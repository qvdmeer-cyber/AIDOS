# AIDOS local bridge

The bridge is the local event-driven orchestration layer. It does not make product decisions.

## Responsibilities

- register project ID ↔ repo ↔ official root ↔ GPT-worker mapping;
- validate project binding before every execution;
- manage Codex session IDs and rotation;
- launch/resume Codex executions;
- maintain execution leases so the same revision is not started twice;
- schedule multiple projects within configurable local resource limits;
- append bridge events and update current project-state projection;
- publish/clean ephemeral review transport;
- activate the correct GPT Worker only when an event requires reasoning;
- respect supervised Windows lock policy;
- collect telemetry and recovery data.

## Non-responsibilities

- product/requirements decisions;
- architecture invention outside accepted scope;
- becoming the canonical store for project truth;
- storing secrets in project/AIDOS repos.

## Desktop GPT trigger

A direct supported ChatGPT event/deep-link API is not assumed. Windows desktop activation/UI automation must be treated as an implementation requiring explicit end-to-end acceptance tests:

1. correct Worker chat selected;
2. wrong worker/project identity rejected by protocol;
3. app foreground/minimized/closed behaviour proven;
4. supervised Windows-lock behaviour proven;
5. failure leaves durable work in `REVIEW_READY` rather than losing it.

The current desktop adapter is transport-only and lives in `bridge/AidosDesktopChatGPT.psm1` with a separate process entrypoint at `bridge/Invoke-AidosDesktopChatGPT.ps1`. It requires an explicit one-time conversation enrollment, stores only transport-routing metadata in `.aidos/runtime/chatgpt`, and uses Windows UI Automation / accessibility APIs as the primary selector with keyboard/clipboard fallback only after exact process/window/conversation proof. The Windows selector starts from a same-session process `MainWindowHandle`, verifies the visible Win32 shell, then correlates that exact handle and process ID with a UIA `Window` root; helper/IME/Electron child windows are not candidates. Explicit `W` Win32 calls use Unicode output marshalling, and conversation proof searches UIA `TextPattern` content because Chromium/WebView controls may split rendered message text across separate accessibility elements. It never changes review decisions; the bridge consumer remains the sole authority for response acceptance, durable decision recording, consume acknowledgement and cleanup.

## Implementation stages

1. contracts + project binding + event/state persistence;
2. Codex launch/resume/session rotation;
3. execution leases + multi-project scheduler;
4. review-ref lifecycle;
5. single-project review package publish/consume/cleanup;
6. ChatGPT desktop trigger prototype;
7. supervised lock gate;
8. crash/restart reconciliation;
8. telemetry + tuning;
9. optional isolated per-project runtimes.

## Single-project execution entry point

The PowerShell 7 bridge and Codex are separate runtimes. On WSL, invoke Codex directly with
`RuntimeKind WSL_LOCAL`. A future Windows-native orchestrator uses `RuntimeKind WINDOWS_WSL`
with an explicit distribution and WSL project root; it launches `wsl.exe` and never treats a
Windows path as a Codex workspace path.

Before dispatch, the bridge revalidates the exact project root/repository and the accepted
preparation snapshot in the Execution. It then acquires one project-local execution lease,
captures `codex exec --json`, and persists the session, terminal result, execution/revision and
Git HEAD. Read-only authority maps to `codex exec --sandbox read-only ...`; filesystem-write
authority maps to `codex exec --approve-for-me ...` with no `--sandbox` flag. `resume` reuses the
persisted session policy and never restates sandbox flags. A clean Codex process termination reaches
`TERMINAL_PENDING`; only declared deterministic execution evidence passing may advance to
`REVIEW_READY`. Missing or failed evidence advances to `EXECUTION_VALIDATION_FAILED` while
preserving the session and terminal evidence for repair. Revision changes while remaining in
`TASK_READY` use a dedicated dispatch-binding event before the lease is acquired; the bridge never
uses `TASK_READY -> TASK_READY` as a generic metadata patch. `Invoke-AidosStartupReconciliation`
fails interrupted work to `RECOVERY_REQUIRED`; it never infers completion.

Review transport is explicit and ephemeral: `Publish-AidosReviewPackage` creates a secret-free
package, publishes a canonical `REVIEW_ASSIGNMENT` envelope and durable review record,
`Invoke-AidosReviewWorker.ps1` can act as a separate transport-neutral Worker/GPT stub that returns
a canonical `REVIEW_RESPONSE` envelope, `Invoke-AidosReviewConsumer` validates the response and
records the durable decision/consume acknowledgement, `Repair-AidosReviewPackage` can explicitly
upgrade a legacy GPT_REVIEWING or RECOVERY_REQUIRED package that is missing canonical assignment
materialization, and `Repair-AidosLegacyReviewAssignmentCorrelation` repairs the narrowly provable
legacy case where the assignment file is already canonical but the durable assignment hash drifted.
`Invoke-AidosReviewCleanup` removes the ephemeral package only after the durable record is complete.
The entrypoint exposes `-Mode Recover` for the assignment-materialization path and
`-Mode RepairLegacyCorrelation` for the hash-correlation repair path.
`-Mode Abandon -ReviewId <id> -Reason <reason>` explicitly closes an inactive, unconsumed,
rejected review transport without deleting its package or inventing a review decision. The durable
record changes only to terminal `ABANDONED`, records the exact binding and reason, and emits
`REVIEW_TRANSPORT_ABANDONED`; reconciliation treats only a valid closure as terminal.

Entry point: `bridge/Invoke-AidosCodex.ps1` (PowerShell 7 only).

## Persistent Local Desktop Agent (Windows host)

`bridge/Invoke-AidosPersistentLocalDesktopAgent.ps1` is a host-infrastructure
wrapper around the existing desktop adapter and review consumer. It owns neither
project state nor review decisions. Its small host-only ledger is under
`%LOCALAPPDATA%\AIDOS\host-agent` for the bound user and contains a singleton lease, heartbeat,
structured JSONL events and a cooperative stop marker.

Install it once from an already authenticated `AIDOS\qvdm` interactive PowerShell
session (an elevated prompt may be needed for task registration):

```powershell
pwsh -File .\bridge\Invoke-AidosPersistentLocalDesktopAgent.ps1 -Command Install -ProjectRoot '\\wsl.localhost\Ubuntu\home\aidos\repos\YOUR-PROJECT'
```

The task uses the `Interactive` task logon type for `AIDOS\qvdm`; it does not run
as a service, store a password, use auto-logon, or create a desktop in another
user session. Maintenance commands are `Start`, `Stop`, `Status`, `Snapshot`,
`HandoffToConsole` and `Uninstall`. `HandoffToConsole` re-queries and identity
checks the current session immediately before `tscon <same-session-id>
/dest:console`, then proves the same session became the console session.

All maintenance operations go through the one entrypoint (replace `PROJECT` with
the Windows-visible project root):

```powershell
pwsh -File .\bridge\Invoke-AidosPersistentLocalDesktopAgent.ps1 -Command Start -ProjectRoot '\\wsl.localhost\Ubuntu\home\aidos\repos\PROJECT'
pwsh -File .\bridge\Invoke-AidosPersistentLocalDesktopAgent.ps1 -Command Stop
pwsh -File .\bridge\Invoke-AidosPersistentLocalDesktopAgent.ps1 -Command Status
pwsh -File .\bridge\Invoke-AidosPersistentLocalDesktopAgent.ps1 -Command Snapshot
pwsh -File .\bridge\Invoke-AidosPersistentLocalDesktopAgent.ps1 -Command HandoffToConsole
pwsh -File .\bridge\Invoke-AidosPersistentLocalDesktopAgent.ps1 -Command Uninstall
```

`Install` is idempotent and updates only the named AIDOS scheduled task. It
refuses registration unless it is currently running in the exact unlocked bound
interactive session. `Uninstall` first requests a graceful stop, then removes
only that task and the bound user's host-agent ledger.

On every tick the agent re-queries WTS topology, rejects a locked/unknown/wrong
user session, reconciles durable review state, invokes the existing gated desktop
adapter only for the active published review, and consumes a validated
`HANDOFF_COMPLETE` sidecar once through `Invoke-AidosReviewConsumer`. `SENT` and
`RECEIVED` are passed back to the adapter recovery path, never sent again. A wake,
agent restart, or RDP reconnect is therefore a fresh reconciliation, not a new
workflow transition.

Run the deterministic Windows regressions with PowerShell 7 before machine
acceptance:

```powershell
pwsh -NoLogo -NoProfile -File .\tests\Bridge.Tests.ps1
pwsh -NoLogo -NoProfile -File .\tests\WindowsPath.Tests.ps1
pwsh -NoLogo -NoProfile -File .\tests\PersistentLocalDesktopAgent.Tests.ps1
```

The last test covers singleton/stale-lease recovery, lock and identity failure,
disconnected-but-unlocked eligibility, console/RDP handoff proof, completed
handoff consumption exactly once, and PREPARED/SENT/RECEIVED restart recovery.
