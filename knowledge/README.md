# AIDOS knowledge

AIDOS knowledge is organized by applicability, not by source project.

```text
knowledge/
├─ core/          always-relevant operating knowledge
├─ capabilities/  e.g. database, auth, deployment, routing, testing
└─ goals/         reusable development-goal/problem patterns
```

Project-specific facts do not belong here.

## Retrieval

Worker selects the minimum useful set for the current execution. The existence of knowledge does not imply it should enter every model context.

## Precedence

```text
accepted Definition/current Execution
> project truth
> AIDOS goal knowledge
> AIDOS capability knowledge
> generic heuristic
```

AIDOS global knowledge cannot silently override accepted/project truth.
