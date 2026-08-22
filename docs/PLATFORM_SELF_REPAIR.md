# Platform self-repair

AIDOS may autonomously repair only platform-owned code. Platform scope is
explicitly allowlisted by repository and path; project state, project
repositories, `.aidos` objects, credentials and review results are never repair
targets.

## Durable lifecycle

```text
DETECTED → ASSIGNED → PATCHED → VALIDATED → SELF_UPDATED → RETRY_PENDING
→ RESOLVED / BLOCKED
```

`bridge/AidosPlatformRepairSupervisor.psm1` persists blocker and assignment
records under the host bridge state root. A failed Thinker transport creates a
platform blocker and a bounded Codex assignment when its classification is
`PLATFORM_TRANSPORT`, `PLATFORM_RUNTIME` or `PLATFORM_INTERFACE`. Unknown or
authority-sensitive failures are `HUMAN_REQUIRED` and remain blocked.

## Repair gates

The repair actor must return a commit, changed paths and passing validation.
`Test-AidosPlatformRepairPaths` rejects paths outside the repository allowlist,
including project state and secret-looking paths. Core may self-update only
after those artifacts are durable and may perform at most one controlled retry.

The supervisor never fabricates a result, changes project state, changes a
Thinker binding or retries an uncommitted transport failure. A repair assignment
is evidence and authority for platform repair only; it is not project execution
authority.
