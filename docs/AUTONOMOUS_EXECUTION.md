# Autonomous Worker execution

## Purpose

After an explicitly accepted Definition reaches `TASK_READY`, AIDOS Core may create and execute a bounded Worker execution without human relay.

The first implementation intentionally preserves the proven single-execution semantics. Multi-workstream parallel execution remains a later orchestration layer rather than being invented inside the Worker adapter.

## Authority sequence

```text
accepted Definition
+ exact preparation binding
+ verified Project Applicability
+ canonical project execution policy

→ bounded EXECUTION.json
→ exact execution/revision state binding
→ execution lease
→ Codex Worker
→ deterministic project validation
→ REVIEW_READY | EXECUTION_VALIDATION_FAILED | RECOVERY_REQUIRED
```

Core owns execution creation, authority, state transitions, leases, validation and persistence. Codex implements only the accepted Definition.

## Initial supported profile

The first autonomous adapter supports the composable profile:

```text
WEB_APPLICATION
+ REACT
```

This is an adapter capability, not a claim that every project with those presets has identical implementation structure. Core therefore does not prescribe `src/client`, `src/server` or another repository layout.

The project must expose the accepted deterministic `npm run validate` gate. Initial structural evidence only requires the npm project manifest; project-owned validation determines the actual application structure and acceptance checks.

Unsupported profiles fail closed as `PROFILE_ADAPTER_REQUIRED` rather than receiving guessed execution semantics.

## Network authority

Network access is not implied by the web/React profile.

The initial adapter enables dependency-network access only when canonical project engineering truth explicitly states both:

- `npm ci` is the reproducible restore path; and
- normal restore is online from the configured npm registry.

The source reference is persisted in the Execution scope and in the execution-planned event. Without that evidence, the same Worker profile receives no network authority.

## Codex sandbox

Filesystem mutation uses the Codex `workspace-write` sandbox. Network access, when project evidence authorizes it, is enabled explicitly inside that sandbox. The adapter does not use `danger-full-access`.

The Worker receives no Git commit or push authority. AIDOS owns durable integration, review and subsequent scheduling.

## Validation

Worker completion is not acceptance. AIDOS runs:

1. execution evidence requirements;
2. every registered project validator (`npm run validate` for this profile);
3. state transition to `REVIEW_READY` only when the combined validation passes.

A validation failure moves to `EXECUTION_VALIDATION_FAILED`; process/runtime failure moves to `RECOVERY_REQUIRED`.

## Current limitation

The initial adapter runs one bounded Worker execution synchronously through the existing project manager path. This is sufficient to prove the full vertical lifecycle before introducing parallel workstreams, dependency scheduling and shared-resource leases.
