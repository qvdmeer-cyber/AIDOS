# Concurrency and recovery

## Multi-project model

AIDOS may keep many projects active simultaneously. Each project has independent canonical state, sessions and event history.

Resource scheduling is a runner concern, not a project-count restriction.

Initial runner policy should be configurable, for example:

```text
max_parallel_codex = 3
max_parallel_heavy_jobs = 1
```

Values are deliberately tunable from observed CPU/RAM/disk behaviour.

## Execution lease

Before launching Codex, the bridge acquires a lease bound to:

```text
project_id
execution_id
revision
runner_id
lease_id
started_at
```

A second worker must not launch the same execution while a valid lease exists.

Lease reconciliation after crash/restart checks actual process/session state plus canonical events instead of blindly assuming the old worker is alive or dead.

`STATE.json` may keep the last execution context after the lease is released, including
`lease_id`, `terminal_result`, `git_head`, `validation_result`, `codex_session_id` and the
execution/revision binding, as historical provenance. That context must not be treated as an
active lease. The active-lease truth source is the presence and contents of
`.aidos/runtime/lease.json`.

## Recovery principle

After power loss, reboot, bridge crash, Codex crash or interrupted Git operation:

1. do not infer completion;
2. load project manifest/current state;
3. replay/inspect append-only events;
4. verify Git head/ref bindings;
5. verify local running process/session if claimed;
6. reconcile ephemeral review packages/refs;
7. derive one safe next state;
8. record a recovery event before resuming.

## Disk safety

Disk exhaustion is a legitimate hard operational stop because it can corrupt builds, package creation and state writes.

The bridge should expose configurable thresholds. Initial policy may warn early and stop launching new heavy executions at critically low free space rather than killing an already-safe execution mid-write.
