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

## Implementation stages

1. contracts + project binding + event/state persistence;
2. Codex launch/resume/session rotation;
3. execution leases + multi-project scheduler;
4. review-ref lifecycle;
5. ChatGPT desktop trigger prototype;
6. supervised lock gate;
7. crash/restart reconciliation;
8. telemetry + tuning;
9. optional isolated per-project runtimes.
