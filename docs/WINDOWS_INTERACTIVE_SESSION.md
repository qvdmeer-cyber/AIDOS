# Windows interactive session gate

The desktop ChatGPT transport is permitted to interact with the Windows UI only when the runner can prove a usable interactive user session. Machine/session availability is an infrastructure condition; it is not a project/workflow state transition.

## Native observation

`bridge/AidosWindowsSession.psm1` obtains a fresh snapshot from Windows-native APIs:

- `ProcessIdToSessionId` binds the orchestrator process to its Windows session;
- `WTSQuerySessionInformationW(..., WTSSessionInfoEx)` supplies connection and lock state;
- `WTSQuerySessionInformationW(..., WTSClientProtocolType)` distinguishes console (`0`) from RDP (`2`);
- `WTSGetActiveConsoleSessionId` records the physical-console session for diagnostics;
- `OpenInputDesktop` proves that the caller can open the current input desktop.

A failed or partial observation never implies permission. Unknown state fails closed.

## Eligibility

Both `SUPERVISED` and the current desktop implementation of `UNATTENDED_ALLOWED` require:

```text
connection_state = ACTIVE
lock_state = UNLOCKED
session_kind in { CONSOLE, RDP }
input_desktop_available = true
```

`UNATTENDED_ALLOWED` means that no human trigger is required while Windows already provides an approved interactive desktop. It does not authorize authentication bypass, automatic unlock, credential injection, security-desktop manipulation, or UI automation against a locked/disconnected desktop.

## Durable waiting overlay

The canonical project remains `REVIEW_READY` while an assignment has not yet been consumed. The desktop adapter's existing transport phase is also preserved:

```text
PREPARED
SENT
RECEIVED
VALIDATED
HANDOFF_COMPLETE
```

Temporary Windows availability is stored orthogonally in `ADAPTER_STATE.json`:

```json
{
  "status": "SENT",
  "interactive_session": {
    "status": "WAITING",
    "reason": "SESSION_DISCONNECTED",
    "session_kind": "RDP"
  }
}
```

The previous compatibility form in which `WAITING_INTERACTIVE_SESSION` replaced `status` is normalized on the next gated invocation. In particular, `delivery_status=SENT` becomes `status=SENT`; reconnect can therefore never authorize a blind resend.

## Resume behavior

`bridge/AidosDesktopSessionGate.psm1` wraps the proven desktop adapter without changing its send/read/validation implementation.

When the native gate blocks interaction:

1. the underlying adapter writes its safe waiting result;
2. the wrapper normalizes it to the original transport phase plus `interactive_session=WAITING`;
3. `INTERACTIVE_SESSION_WAIT_STARTED` is recorded when possible;
4. the launcher waits by repeatedly querying current Windows state unless waiting was explicitly disabled;
5. after the session becomes eligible, `interactive_session=AVAILABLE` and `INTERACTIVE_SESSION_WAIT_ENDED` are recorded;
6. the exact same review invocation resumes through the existing adapter state.

Because `PREPARED` and `SENT` survive the wait, unlock/reconnect cannot duplicate Codex execution, review publication, assignment send, accepted response, consume acknowledgement, or cleanup.

The polling loop is a wake mechanism only. Every retry obtains a fresh native snapshot; no lock/unlock event or prior observation is treated as authority.

## Launcher policy

`Invoke-AidosDesktopChatGPT.ps1` defaults to:

```text
SessionPolicy = SUPERVISED
WaitForInteractiveSession = true
InteractiveSessionPollSeconds = 2
InteractiveSessionWaitTimeoutSeconds = 0  # no timeout
```

For diagnostic/manual runs, `-WaitForInteractiveSession:$false` persists the waiting overlay and returns immediately. A later invocation resumes from the persisted `PREPARED` or `SENT` phase.

## Dedicated-machine acceptance smoke

The milestone is accepted only after the dedicated Windows machine proves at least:

- console unlocked -> available;
- console lock before send -> no send, phase `PREPARED` preserved;
- unlock -> one send;
- lock/disconnect after `SENT` -> `SENT` preserved and no resend;
- RDP disconnect -> unavailable;
- RDP reconnect -> resume exactly once;
- bridge restart while waiting -> same review/revision resumes without duplicate work;
- unknown/native query failure -> fail closed.
