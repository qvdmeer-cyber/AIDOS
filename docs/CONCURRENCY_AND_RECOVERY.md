# Concurrency and recovery

## One AIDOS, many projects

AIDOS may keep many isolated projects active simultaneously. Each project has independent canonical state, credentials/authority, workstreams, sessions and event history.

Resource scheduling is a runner concern, not a project-count restriction.

Initial runner policy remains configurable, for example:

```text
max_parallel_codex = 3
max_parallel_heavy_jobs = 1
```

Values are tuned from observed CPU/RAM/disk behaviour.

## Project-internal workstream concurrency

A project may contain multiple durable workstreams as defined in `docs/WORKSTREAM_ORCHESTRATION.md` and `schemas/workstream.schema.json`.

AIDOS may execute workstreams in parallel only when the dependency graph, scope ownership, shared contracts and resource claims make that safe.

Parallelism is therefore constrained by:

- hard/soft/integration dependencies;
- path/surface/output ownership;
- shared contract version/binding;
- exclusive shared resources;
- integration-gate readiness;
- accepted Definition/release scope.

A workstream must not gain authority merely because a sibling workstream has it.

## Existing execution lease

Before launching Codex, the current Bridge acquires an execution lease bound to:

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

`STATE.json` may keep historical execution context after release. Active-lease truth remains `.aidos/runtime/lease.json`.

## Workstream/shared-resource leases

Parallel work introduces a conceptual lease layer for resources that cannot safely be mutated concurrently, such as:

- schema/migration ownership;
- deployment/runtime environments;
- generated shared artifacts;
- merge-sensitive integration refs;
- other exclusive shared state.

Workstreams declare `resource_claims` as `SHARED_READ`, `EXCLUSIVE_WRITE` or `EXCLUSIVE_RUNTIME`. AIDOS must acquire required exclusive leases before activating a conflicting execution Worker.

**Implementation status:** project/revision execution lease semantics are implemented/proven. Generic workstream/shared-resource lease acquisition is not yet implemented and remains a roadmap item.

## Integration gates

Parallel local completion is not project integration.

Applicable integration gates must pass before AIDOS accepts the combined result, including shared-contract compatibility, combined build/test, data/migration compatibility, representative runtime checks and Definition/release convergence.

## Recovery principle

After power loss, reboot, Bridge/Codex crash or interrupted Git operation:

1. do not infer completion;
2. load project + workstream manifests/current projections;
3. replay/inspect append-only events;
4. verify Git head/ref bindings;
5. verify active process/session/lease claims;
6. reconcile review packages/refs and Human Input Requests;
7. derive one safe next state/actor per affected project/workstream;
8. record recovery events before resuming.

Temporary GPT/Codex sessions may be replaced. Durable project/workstream identities, bindings, requests and leases may not be reconstructed from chat memory.

## Disk safety

Disk exhaustion remains a legitimate hard operational stop. The Bridge should warn early and stop launching new heavy work at critically low free space rather than killing an already-safe execution mid-write.
