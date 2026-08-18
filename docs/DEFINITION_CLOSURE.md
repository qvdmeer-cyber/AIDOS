# Definition closure and final acceptance

## Purpose

Auto Define may resolve Definition applicability and surfaces autonomously, but execution authority still requires one explicit final human acceptance of the converged Definition.

Definition closure is therefore a Core-owned transaction rather than another Thinker preference decision.

## Closure sequence

```text
WAITING_DEFINITION
+ no pending Definition actor assignment
+ Definition progress ready
+ Definition applicability resolved
+ decision governance valid

→ persist canonical DEFINITION.json as USER_REVIEW
→ publish exactly one FORMAL_DEFINITION_ACCEPTANCE Human Input Request
→ WAITING_USER
```

The canonical Definition binds the accepted project goal, resolved Definition surfaces, acceptance boundary, out-of-scope items, source references, decision references, Definition progress and applicability.

## Human outcomes

### ACCEPT

```text
Human Input ACCEPT
→ DEFINITION.status = ACCEPTED
→ accepted_by / accepted_at persisted
→ DEFINITION_ACCEPTED event
→ project state TASK_READY
```

Only this transition authorizes execution planning.

### REOPEN

```text
Human Input REOPEN
→ DEFINITION.status = REOPENED
→ unresolved_assumptions reopened
→ project state WAITING_DEFINITION
→ Auto Define resumes from durable state
```

A reopen preserves the prior proposal and Human Input evidence; it does not rewrite history or authorize execution.

## Authority boundary

Final Definition acceptance is always `HUMAN_REQUIRED`. Auto Define may minimize the decisions needed to reach the gate, but it may never accept the final Definition on behalf of the operator.

AIDOS Core owns readiness validation, canonical persistence, Human Input binding and state transitions. The Thinker does not directly set `ACCEPTED` or `TASK_READY`.
