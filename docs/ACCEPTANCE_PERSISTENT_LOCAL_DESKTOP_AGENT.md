# Persistent Local Desktop Agent — Acceptance

Status: **ACCEPTED**  
Accepted on: **2026-08-17**  
Scope: Windows interactive host runtime for autonomous desktop ChatGPT Worker transport independent of an attached RDP client.

## Accepted outcome

AIDOS can keep its Windows-facing desktop review host agent alive in the authenticated `AIDOS\qvdm` interactive session when an RDP client disconnects, provided the session remains eligible for interactive desktop automation.

RDP is remote management only. It is not runtime authority.

The agent fails closed when the interactive session is temporarily unavailable/locked and resumes automatically after the same authorized session becomes usable again. It does not auto-login, unlock Windows, bypass authentication, or create a privileged desktop service.

## Machine-tested acceptance evidence

Dedicated Windows + WSL2 host, project `AIDOS-BRIDGE-SMOKE`.

### Persistent host process

Observed after installation and recovery fixes:

- Scheduled Task: `AIDOS Persistent Local Desktop Agent`
- task state: `Running`
- host-agent PID: `20280`
- agent phase: `RUNNING`
- authorized user: `AIDOS\qvdm`
- project root: `\\wsl.localhost\Ubuntu\home\aidos\repos\AIDOS-BRIDGE-SMOKE`
- failure count: `0`

### Desktop ChatGPT shell binding

The same ChatGPT Classic shell remained healthy across the RDP/console lifecycle:

- process: `ChatGPT Classic`
- PID: `17376`
- Windows session: `1`
- main window handle: `657418`
- UI Automation shell proof: accepted

### Review lifecycle recovery

Revision 8 review `b96eaae0-a267-4733-85ca-a31e8e6b0395` was recovered and completed by the persistent agent without re-sending the already validated Worker response.

Binding/evidence checkpoints:

- assignment SHA-256: `1db1ff93641543b96ccb98ac5c121df097f918a0a95fed461f80c6f351dd46da`
- package manifest SHA-256: `0bd330c39367a2154a1085cc561c79d41826dc7e14e490f1fabe333533466223`
- response SHA-256: `c06256473e9d8b00731271150d7189c0a2d16ac63de4aa42d711e4a3b296d8aa`
- Worker outcome: `PASS`
- durable transport lifecycle reached `CONSUMED` and then `CLEANED`

This proves exactly-once consume/cleanup recovery for the existing response path used by this smoke.

### RDP-independent ticking

The runtime event ledger continued producing host-agent ticks through the RDP-to-console/reconnect cycle.

Relevant UTC events:

```text
2026-08-17T20:21:49Z  CLEAN
2026-08-17T20:21:55Z  CLEAN
2026-08-17T20:22:01Z  CLEAN
2026-08-17T20:22:07Z  CLEAN
2026-08-17T20:22:13Z  CLEAN
2026-08-17T20:22:19Z  CLEAN
2026-08-17T20:22:24Z  WAITING_INFRASTRUCTURE / SESSION_LOCKED
2026-08-17T20:22:31Z  CLEAN
2026-08-17T20:22:37Z  CLEAN
2026-08-17T20:22:42Z  CLEAN
2026-08-17T20:22:48Z  CLEAN
... continuing approximately every six seconds ...
2026-08-17T20:24:38Z  CLEAN
```

The single `SESSION_LOCKED` observation during the topology transition is accepted behaviour: the agent did not perform desktop work while the session was ineligible and resumed without manual recovery once the authorized interactive session was available again.

## Acceptance invariants

The milestone is accepted only with these invariants preserved:

1. RDP connection state does not own runtime lifecycle.
2. Desktop automation is bound to the exact authorized Windows user/session.
3. Locked, unknown, mismatched, logged-off, or otherwise ineligible session state blocks desktop action fail-closed.
4. No auto-login, auto-unlock, credential injection, authentication bypass, or service-desktop automation.
5. Sleep/hibernate may suspend execution naturally; durable state is reconciled after wake.
6. Review assignment/response binding, hash validation, consume acknowledgement and cleanup remain authoritative Bridge semantics.
7. Reinstall/restart must load fresh runtime code and must not create concurrent host-agent ownership.
8. Host-agent status/heartbeat is operational state and must not replace project workflow state.

## Closure

The Persistent Local Desktop Agent milestone is closed. Further work on this layer is defect-driven only unless a later accepted architecture change explicitly reopens it.

The next core milestone is **Runtime Observability & Operator API**. It must expose machine-readable status and safe control intents without implementing the separate AIDOS Interface UI project.
