# AIDOS — Persistent Local Desktop Agent implementation assignment

## Purpose

Implement the Windows host agent that allows AIDOS to run the desktop ChatGPT review loop autonomously on the dedicated AIDOS machine without requiring an attached RDP client and without requiring the human operator to copy/paste PowerShell commands during normal operation.

This is **AIDOS-core scope**. It is not part of the separate AIDOS Interface project.

## Proven machine facts

Treat these as established acceptance evidence from the dedicated AIDOS Windows machine unless a new machine test contradicts them:

1. Windows user: `AIDOS\\qvdm`.
2. AIDOS repo in WSL: `/home/aidos/repos/AIDOS`.
3. Windows repo path: `\\\\wsl.localhost\\Ubuntu\\home\\aidos\\repos\\AIDOS`.
4. Codex CLI on WSL is available at `/home/aidos/.local/bin/codex`.
5. ChatGPT desktop process name on this machine is `ChatGPT Classic`.
6. A ChatGPT Classic shell process has a non-zero `MainWindowHandle` and remains alive with the same PID/window handle across an RDP-to-console handoff.
7. `tscon <session-id> /dest:console` successfully transfers the already-authenticated `qvdm` session from RDP ownership to the physical console without logging out, relaunching ChatGPT, or changing the session id.
8. After that handoff, AIDOS successfully sent a Worker review assignment through ChatGPT Classic UI Automation and later recovered/validated the existing Worker response without resending.
9. The desktop adapter reached `HANDOFF_COMPLETE` for smoke review `b96eaae0-a267-4733-85ca-a31e8e6b0395`, revision 8.
10. Lock is a real stop condition. RDP disconnect by itself is not a stop condition. Sleep/hibernate naturally suspends execution and must reconcile after wake.

## Required architecture

Conceptually:

```text
AIDOS Windows host
  -> Persistent Local Desktop Agent
       -> owns/observes the authenticated qvdm interactive Windows session
       -> observes lock/session/topology state
       -> keeps ChatGPT Classic health/binding observable
       -> performs safe RDP -> console handoff when required
       -> drives/reconciles the desktop ChatGPT adapter
       -> drives/reconciles review consume/cleanup
       -> resumes durable AIDOS work after unlock/wake/reconnect

RDP
  -> remote management/observation only
  -> never runtime authority
  -> may attach to the same authenticated session
  -> may be handed back to the physical console without changing AIDOS project authority
```

Do not create a second conceptual AIDOS instance and do not treat the agent as project state. The agent is host/runtime infrastructure for the one AIDOS system.

## Security invariants

Must remain true:

- no auto-login;
- no password storage/injection;
- no auto-unlock;
- no authentication bypass;
- no session hijack of another user;
- no RDP client-presence requirement;
- lock must block desktop interaction;
- unknown/mismatched session identity must fail closed;
- project/review/execution durable state remains authoritative;
- agent restarts must reconcile from durable state rather than infer completion from memory;
- no blind resend after `SENT`/`RECEIVED`;
- all review binding/hash validation remains unchanged and fail-closed.

## Required implementation

### 1. Persistent agent executable/entrypoint

Add a durable Windows-facing agent entrypoint in the AIDOS repo. PowerShell is acceptable as the host implementation language for V1, but normal operation must not require the human to invoke individual bridge commands manually.

The agent must have:

- singleton ownership/lease so two agents cannot drive the same desktop concurrently;
- durable host-agent status/heartbeat separate from project workflow state;
- graceful stop;
- bounded retry/backoff;
- structured event/log output;
- startup reconciliation.

### 2. Interactive startup/bootstrap

Provide an idempotent installer/bootstrap for the dedicated machine.

It should register/start the agent only in an existing interactive `qvdm` token/session (for example an interactive-token scheduled task or equivalent appropriate Windows user-startup mechanism). It must not use a non-interactive service desktop for UI Automation.

Installation may require one explicit elevated human action. After installation, normal AIDOS operation must not require repeated PowerShell copy/paste.

Provide status/uninstall commands as well.

### 3. Session ownership and topology

Use the existing native Windows/WTS session primitives and topology work already present in `bridge/AidosWindowsSession.psm1` and related files.

The agent must distinguish at least:

- authenticated session exists / missing;
- console vs RDP protocol;
- ACTIVE/CONNECTED/DISCONNECTED and terminal states;
- LOCKED vs UNLOCKED;
- process session id vs observed target session id;
- physical console session id;
- ChatGPT Classic process/shell health.

RDP protocol/connection state is diagnostic unless it proves loss/mismatch of the authenticated interactive session. `DISCONNECTED` alone must not block AIDOS.

### 4. RDP -> console handoff

Implement a safe handoff operation for the current authorized AIDOS user session using the Windows-supported `tscon <authorized-session-id> /dest:console` behavior proven on this machine.

Requirements:

- only the current configured AIDOS user/session may be handed off;
- verify exact session identity immediately before handoff;
- never select another logged-on user;
- no password argument or credential injection;
- make the operation idempotent: if already console-owned, do nothing;
- record before/after topology evidence;
- if handoff cannot be proven, fail closed and leave durable AIDOS work pending.

The agent should expose a machine command/API for explicit handoff. If automatic handoff is implemented, use a conservative trigger and document it. Do not rely on an RDP disconnect event as authoritative state; always re-query WTS state.

### 5. ChatGPT Classic health

Canonical process name for this machine is `ChatGPT Classic`, while keeping explicit configuration override possible.

The agent must check:

- process in the expected Windows session;
- exactly one usable top-level ChatGPT shell;
- non-zero window handle;
- UI Automation root available;
- enrolled conversation binding still valid when an action is required.

Do not relaunch or re-enroll blindly if exact durable binding cannot be proven. Surface a bounded recoverable/error state instead.

### 6. Desktop review orchestration

Integrate the existing desktop adapter/session gate rather than duplicate it.

The agent should autonomously:

1. detect a published/recoverable review requiring desktop Worker transport;
2. reconcile adapter state;
3. wait while genuinely locked/unavailable;
4. drive ChatGPT review when authorized;
5. recover `SENT`/`RECEIVED` without blind resend;
6. on `HANDOFF_COMPLETE`, invoke the existing review consumer using the validated `REVIEW_RESPONSE.json`;
7. execute existing review cleanup/reconciliation policy where appropriate;
8. continue the AIDOS workflow.

Use `bridge/Invoke-AidosReview.ps1` / existing bridge functions for consume/cleanup rather than inventing a second review state machine.

### 7. Finish existing smoke review before destructive cleanup

Current smoke review:

- project: `AIDOS-BRIDGE-SMOKE`
- execution: `SMOKE-EXEC-001`
- revision: `8`
- review: `b96eaae0-a267-4733-85ca-a31e8e6b0395`
- desktop adapter: proven `HANDOFF_COMPLETE`
- validated response sidecar exists under `.aidos/runtime/chatgpt/reviews/<review-id>/REVIEW_RESPONSE.json`

Before using this smoke as closed evidence, consume that validated response through the existing review consumer and then reconcile/cleanup according to existing contracts. Do not fabricate a decision and do not regenerate/resend the review.

### 8. Lock/unlock and sleep/wake recovery

Required behavior:

- unlocked authorized session -> agent may act;
- locked -> no desktop actions; durable project/review state remains unchanged;
- unlock -> re-query topology + shell + durable state, then resume exact pending phase;
- sleep/hibernate -> process suspension is not a workflow transition;
- wake -> startup/recovery reconciliation before any send/action;
- session mismatch/logoff -> stop desktop activity and report infrastructure unavailability.

Do not turn these availability conditions into canonical project workflow states.

### 9. Operator UX

Provide concise machine commands for at least:

- install;
- start;
- stop;
- status;
- explicit `handoff-to-console`;
- uninstall;
- one diagnostic snapshot.

Normal daily AIDOS use should not require these commands; they are maintenance controls.

## Acceptance tests

Add deterministic tests plus machine smoke instructions. Acceptance requires all of the following:

1. Existing bridge/unit tests remain green.
2. Agent singleton/lease behavior is tested.
3. `DISCONNECTED + UNLOCKED` does not become a security stop solely because no RDP client is attached.
4. `LOCKED` blocks desktop action.
5. Unknown/mismatched session fails closed.
6. Console-owned authorized session is eligible.
7. RDP-owned authorized session can be handed to console and the same session id is preserved.
8. ChatGPT Classic main shell PID/window handle can survive handoff (machine smoke; already observed, re-prove in final acceptance).
9. A review can be sent/read while console-owned without an attached RDP client.
10. `SENT`/`RECEIVED` recovery never blindly resends.
11. A validated desktop response is automatically consumed exactly once.
12. Agent restart during PREPARED, SENT, RECEIVED, and HANDOFF_COMPLETE is idempotently reconciled.
13. Lock during pending work waits; unlock resumes.
14. Wake/restart reconciliation does not invent project/review state.
15. Installer is idempotent and uninstall removes only agent-owned machine configuration.

## Definition of done

The milestone is done when the dedicated AIDOS machine can be left powered on and unlocked, with ChatGPT Classic available in the authenticated AIDOS user session, and AIDOS can continue its GPT↔Codex development/review loop after the operator disconnects RDP, without further manual PowerShell command choreography.

A human may still be required for explicit AIDOS human gates, authentication, machine unlock, security prompts, and other intentional human-authority boundaries.

## Implementation method

Codex should:

1. inventory the current AIDOS bridge/session/review contracts before editing;
2. preserve concurrent/newer `main` work;
3. implement in small commits;
4. run deterministic tests after each meaningful slice;
5. avoid broad rewrites of the already-proven desktop adapter;
6. prefer wrapping/composition around existing bridge contracts;
7. persist architecture/docs/tests with the implementation;
8. stop at a human-required machine bootstrap or acceptance action rather than bypassing it.
