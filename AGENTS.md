# AIDOS repository agent instructions

This repository is the single source of truth for the **private AIDOS runtime method, orchestration/control plane, Definition/Worker/Execution agents, reusable execution tools/validators and generalized learning**.

## System model

There is conceptually one AIDOS runtime managing multiple isolated project instances. A project is not its own AIDOS. GPT/Codex sessions are temporary actors and never canonical workflow state.

## Ecosystem boundaries

- Shared stable preparation/decision contracts belong in `qvdmeer-cyber/AIDOS-Contracts`.
- Distributable Project Baseline + Existing Project Discovery belong in `qvdmeer-cyber/AIDOS-Builder`.
- Project/customer truth and durable project/workstream/decision state belong in the project repository.
- The external AIDOS Interface is a separate client layer/project; do not implement its UI/orchestration in Core.

## Hard boundaries

- Do not reimplement Builder Baseline/Discovery completeness logic in Core.
- Do not copy project strategy, customer context or secrets into AIDOS Core.
- For `EXISTING_PROJECT`, do not begin Definition/Execution without current closure-compatible preparation.
- Discovery Authority never grants execution/write authority.
- Definition progress/applicability/decision state is durable project-local state, not chat memory.
- **No silent inference becomes durable project truth.** Every Definition resolution must be system-defined, evidence-verifiable, a policy-valid Auto Decision or a human decision.
- **Classify authority before asking:** `SYSTEM_INVARIANT`, `REPO_VERIFIABLE`, `AUTO_DECIDABLE`, `HUMAN_REQUIRED`.
- **Confidence never expands authority.** Fail closed on low confidence, irreversibility, material impact/evidence gaps, materially equivalent alternatives or uncertain/out-of-bounds authority.
- **Do not manufacture binary choices.** Human options must match the real material decision space.
- **After every human Definition answer, rerun Auto Define over all remaining unresolved concerns before asking again.**
- Composable profiles are hypotheses/accelerators only; verified/accepted project truth wins.
- A project-applicable development surface may not be silently omitted from a Definition.
- **AIDOS owns control flow.** Thinkers/Workers emit durable results/events/requests; they do not directly start/resume each other.
- Workstream scope is explicit; sibling-owned scope/shared contracts may not be silently mutated.
- Human input is first-class and channel-independent through durable Human Input Requests.
- External controls carry intent only; no client/UI manipulates Codex/state/project files outside orchestration.
- Progress/ETA are estimates only; Definition/evidence/validation/integration/release gates determine actual completion.
- Statistical patterns are observations, not automatic system rules.
- Generic AIDOS knowledge may never silently override accepted project truth, Definition or frozen Launch Definition.
- Once accepted launch criteria pass, improvement alone is insufficient grounds to delay release.

## Actor model

Abstract actor roles are `THINKER`, `WORKER`, `HUMAN`. Preserve existing concrete identities: `DEFINITION_AGENT` and reasoning/review `WORKER_AGENT` serve Thinker roles; `EXECUTION_AGENT`/Codex serves technical Worker role.

## AIDOS-owned actor transition

```text
AIDOS selects actor from durable state
→ activate exact project/workstream/binding
→ actor emits durable event/result/Human Input Request
→ AIDOS validates/reconciles
→ AIDOS selects next valid actor
```

Session replacement must preserve this pattern.

## Auto Define / decision authority

Read shared AIDOS-Contracts Decision Governance 0.1.0 and `docs/AUTO_DEFINE.md`.

```text
SYSTEM_INVARIANT
→ resolve from AIDOS contract/governance source

REPO_VERIFIABLE
→ resolve from authorized project-local evidence

AUTO_DECIDABLE
→ Decision Assessment
→ persist AUTO_DECISION only when policy passes
→ otherwise HUMAN_REQUIRED

HUMAN_REQUIRED
→ durable Human Input Request
```

Only `AUTO_DECIDABLE` is an autonomous project choice. System invariants and repository facts are direct resolution classes, not Auto Decisions.

Definition Auto Decisions live at:

```text
.aidos/definitions/<definition_id>/v<version>/decisions/<decision_id>.json
```

Use `tools/New-AidosDefinitionAutoDecision.ps1` / `tools/Test-AidosAutoDecision.ps1`. Bind affected surfaces through `PROGRESS.json` decision refs. Preserve supersession lineage rather than rewriting history.

Auto Define runs to a fixed point at Definition start/resume, after human answers, after material new evidence and after reopen/supersession. Final Definition `ACCEPTED` remains explicit human governance.

Project Baseline Auto Define is Builder-owned under the same shared Contracts policy. Do not reimplement Baseline completeness here.

## Workstreams

An accepted Definition may be decomposed into zero/one/many workstreams. Parallelization is optional and dependency-driven. Use `schemas/workstream.schema.json` and `docs/WORKSTREAM_ORCHESTRATION.md`.

A local workstream result is not automatically an integrated project result. Applicable integration gates must pass. Current execution lease semantics remain authoritative; generic shared-resource/workstream leases remain roadmap until runtime-proven.

## Control plane and Human Input

Use `schemas/control-intent.schema.json`, `schemas/human-input-request.schema.json`, `docs/CONTROL_PLANE.md`, `protocols/INTERRUPTION_PROTOCOL.md`.

The current top-level `WAITING_USER` state remains valid runtime semantics. Human Input Requests now may retain Auto Define authority classification, assessment ref and stop reason.

## Project/Definition applicability

Reusable profile categories remain `PRODUCT_ARCHETYPE`, `CAPABILITY`, `INTEGRATION`, `STACK`, `INFRASTRUCTURE`, `EXPOSURE_RISK`.

Project applicability: `.aidos/profile/PROJECT_APPLICABILITY.json`.
Definition applicability: `.aidos/definitions/<definition_id>/v<version>/APPLICABILITY.json`.

Precedence:

```text
verified/accepted project truth
> explicit project override
> composed preset result
> generic heuristic
```

## Definition progress

Definition convergence lives at `.aidos/definitions/<definition_id>/v<version>/PROGRESS.json`. A new/rotated chat reads durable progress/decisions/Human Input Requests before continuing.

After any resolution, persist → update affected surfaces/applicability → validate → rerun Auto Define. After a human decision, show full current surface progress before any next human question.

## Progress / ETA

Use `schemas/progress-estimate.schema.json` and `docs/PROGRESS_AND_ESTIMATION.md`. Never use an estimate as acceptance authority.

## Observability and learning

Use `docs/TELEMETRY.md`, `protocols/LEARNING_PROTOCOL.md`, `schemas/system-insight.schema.json`.

Auto Define telemetry includes autonomous decision counts/confidence, revision/supersession rates, human overrides and reasons. These may create observations/hypotheses but may never automatically loosen Decision Governance.

Learning maturity remains:

```text
OBSERVATION
→ HYPOTHESIS / learning candidate
→ explicit review/adoption
→ ADOPTED_IMPROVEMENT
```

## Durable state and recovery

Chats/sessions are disposable. Essential state is reconstructed from project/workstream objects, Definition/Baseline decisions, events, Git bindings, leases, reviews, Human Input Requests and canonical project sources.

Do not recover authority from prose summaries when durable state exists.

## Changes to AIDOS itself

Prefer evidence → observation/hypothesis → provenance/review → explicit adoption → validator/tool/skill where possible. Executable prevention is preferred when machine-detectable, but only after explicit adoption.
