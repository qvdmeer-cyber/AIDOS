# Windows interactive session gate

The desktop ChatGPT transport may interact with the Windows UI only when the runner can prove that its logged-on user session is not locked and has not disappeared. RDP connectivity is an observation and remote-control channel; it is not runtime authority.

## Intended dedicated-machine behavior

AIDOS continues autonomously while the machine is powered and the bound Windows user session remains unlocked, including when an RDP client disconnects. AIDOS pauses interactive ChatGPT work only when Windows security/session state actually removes that authority, most importantly when the session is locked or no longer valid.

Sleep, hibernate and power-off suspend or terminate the process rather than creating an AIDOS workflow state. After resume/restart, the bridge must re-query current Windows state before any new interactive action.

## Native observation

`bridge/AidosWindowsSession.psm1` obtains a fresh snapshot from Windows-native APIs:

- `ProcessIdToSessionId` binds the orchestrator process to its Windows session;
- `WTSQuerySessionInformationW(..., WTSSessionInfoEx)` supplies connection and lock state;
- `WTSQuerySessionInformationW(..., WTSClientProtocolType)` distinguishes console (`0`) from RDP (`2`);
- `WTSGetActiveConsoleSessionId` records the physical-console session for diagnostics;
- `OpenInputDesktop` records desktop readiness for the transport.

A failed or partial WTS observation never implies permission. Unknown lock/session identity fails closed.

## Machine/session eligibility

Both `SUPERVISED` and the current desktop implementation of `UNATTENDED_ALLOWED` require:

```text
session_id == process_session_id
lock_state = UNLOCKED
session_kind in { CONSOLE, RDP }
connection_state not in { DOWN, RESET, LISTEN, INIT, UNKNOWN }
```

`connection_state = DISCONNECTED` is explicitly allowed for an RDP session. Disconnecting an RDP client does not close the logged-on Windows session, and therefore does not itself revoke AIDOS runtime authority.

`input_desktop_available` is no longer a machine-authorization condition. It is transport readiness. During an RDP connect/disconnect transition, UI/Desktop APIs may be temporarily unavailable even though the session remains unlocked. That condition is classified as `DESKTOP_TRANSITION_UNAVAILABLE` and automatically retried; it is not a human wait condition.

`UNATTENDED_ALLOWED` still does not authorize authentication bypass, automatic unlock, credential injection, security-desktop manipulation, or UI automation against a genuinely locked session.

## Durable waiting overlay

The canonical project remains `REVIEW_READY`/`GPT_REVIEWING` according to the existing review lifecycle. The desktop adapter's transport phase is preserved independently:

```text
PREPARED
SENT
RECEIVED
VALIDATED
HANDOFF_COMPLETE
```

A genuine machine/session block can be represented orthogonally in `ADAPTER_STATE.json`:

```json
{
  "status": "SENT",
  "interactive_session": {
    "status": "WAITING",
    "reason": "SESSION_LOCKED",
    "session_kind": "RDP"
  }
}
```

A transient desktop transition may temporarily use the same overlay with `reason=DESKTOP_TRANSITION_UNAVAILABLE`, but the normal launcher automatically retries it. `WAITING` with `reason=NONE` is invalid.

## RDP disconnect semantics

RDP transitions are explicitly modeled but do not pause AIDOS:

```text
RDP ACTIVE + UNLOCKED
→ RDP DISCONNECTED + UNLOCKED
→ AIDOS remains authorized
→ desktop transport retries transient UI/Desktop transition if needed
→ ChatGPT send/read continues if the disconnected session exposes usable UI Automation
```

The final capability boundary is empirical: Windows preserves the disconnected session, but ChatGPT Classic/Chromium UI Automation must be machine-tested while disconnected. If UIA itself does not remain functional for long-lived disconnected sessions, the next architecture step is a stable local-console desktop agent, not treating RDP connection as authority and not bypassing Windows security.

## Lock semantics

Lock is different from disconnect:

```text
UNLOCKED
→ LOCKED
→ already-running non-interactive Codex may finish
→ durable evidence/review state may be written
→ no new interactive ChatGPT action starts
→ UNLOCK restores eligibility after a fresh native query
```

Unlock never creates new work and never resets transport phase; existing idempotency remains authoritative.

## Dedicated-machine acceptance smoke

The milestone is accepted only after the dedicated Windows machine proves at least:

- active RDP unlocked -> eligible;
- RDP disconnect while unlocked -> remains machine-policy eligible;
- RDP disconnect before send -> same review continues without requiring reconnect, if ChatGPT UIA remains usable;
- transient desktop unavailability during disconnect -> automatic retry, no duplicate send;
- RDP reconnect -> no duplicate work;
- lock before send -> no send, phase `PREPARED` preserved;
- unlock -> one send;
- lock after `SENT` -> `SENT` preserved and no resend;
- bridge restart while genuinely waiting -> same review/revision resumes without duplicate work;
- unknown/native query failure -> fail closed.

## Persistent host-agent machine smoke

After one-time task installation, use `Snapshot` to capture the authorized user,
session id, console/RDP topology, lock state and ChatGPT Classic shell PID/window
handle. With a known pending test review, capture the PID/window handle, invoke
`HandoffToConsole`, then capture `Snapshot` again. Acceptance requires the same
authorized session id and the same ChatGPT shell PID/window handle. Disconnect the
RDP client and verify the host heartbeat continues, then verify a console-owned
review can progress without reconnecting. Lock before a pending send and verify
the adapter phase remains unchanged; unlock and verify it resumes that phase.

For the existing smoke review `b96eaae0-a267-4733-85ca-a31e8e6b0395`, run one
unlocked `Tick` (or let the installed task tick) against its project root. It must
consume the existing validated `REVIEW_RESPONSE.json` through the bridge consumer
and reconciliation/cleanup path. Do not publish, resend, or fabricate a response.
