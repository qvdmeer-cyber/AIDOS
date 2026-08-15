# Core knowledge: boundaries

ID: `CORE-BOUNDARIES-001`
Status: `PROVEN`

## Rule

Autonomy should be bounded by machine-verifiable project/execution identity wherever practical, not merely by conversational instruction.

Before execution, bind and validate project ID, repository, official root, branch/ref, accepted Definition and execution revision. Fail closed on mismatch.

## Rationale

Wrong-project, wrong-root and stale-execution mistakes are high-impact and mechanically detectable; model attention should not be the primary control.
