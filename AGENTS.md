# AIDOS repository agent instructions

This repository is the single source of truth for the **private AIDOS runtime method, orchestration/control plane, Definition/Worker/Execution agents, reusable execution tools/validators and generalized learning**.

## System model

There is conceptually one AIDOS runtime managing multiple isolated project instances:

```text
AIDOS
├─ Project A
├─ Project B
└─ Project C
```

A project is not its own AIDOS. GPT/Codex chats and sessions are temporary actors and are never canonical project/workflow state.

## Ecosystem boundaries

- Project Baseline + Discovery Closure/CPS contracts belong in `qvdmeer-cyber/AIDOS-Contracts`.
- Distributable Project Baseline + Existing Project Discovery procedures belong in `qvdmeer-cyber/AIDOS-Builder`.
- Project/customer truth and durable project/workstream state belong in the project repository.
- The future external AIDOS Interface is a separate client layer/project; do not implement its UI/orchestration in Core.

## Hard boundaries

- Do not add organisation-documentation procedures to AIDOS.
- Do not reimplement Builder preparation/completeness logic here.
- Do not copy project strategy, customer context or secrets into AIDOS Core.
- For `EXISTING_PROJECT`, do not begin Definition/Execution without current closure-compatible preparation.
- Discovery Authority never grants execution/write authority.
- Definition progress/applicability is durable project-local state, not chat memory.
- After every human Definition decision, persist/update/validate progress before asking the next question.
- Composable profiles are hypotheses/accelerators only; verified/accepted project truth wins.
- A project-applicable development surface may not be silently omitted from a Definition.
- **AIDOS owns control flow.** Thinkers/Workers emit durable results/events/requests; they do not directly start or resume each other.
- **Workstream scope is explicit.** A workstream may not silently mutate sibling-owned scope or shared contracts.
- **Human input is first-class.** Genuine human boundaries publish a durable Human Input Request; do not rely on a specific chat surviving.
- **External controls carry intent only.** No client/UI may directly manipulate Codex processes, state files or project files outside AIDOS orchestration.
- Progress/ETA are estimates only; Definition/evidence/validation/integration/release gates determine actual completion.
- Statistical patterns are observations, not automatic system rules. Adoption requires explicit governance.
- Generic AIDOS knowledge may never silently override accepted project truth, Definition or frozen Launch Definition.
- Once accepted launch criteria pass, improvement alone is insufficient grounds to delay release.

## Actor model

Mature actor roles:

```text
THINKER
WORKER
HUMAN
```

- Thinker: reasoning/planning/review.
- Worker: bounded technical execution/mutation.
- Human: genuine product/risk/authority decisions.

Preserve existing concrete runtime identities:

- `DEFINITION_AGENT` and current reasoning/review `WORKER_AGENT` may serve Thinker roles.
- `EXECUTION_AGENT` / Codex serves the technical Worker role.

Do not rename current persisted reviewer identities/contracts merely to match the abstraction.

## AIDOS-owned actor transition

Canonical pattern:

```text
AIDOS selects actor from durable state
→ activate exact project/workstream/binding
→ actor emits durable event/result/Human Input Request
→ AIDOS validates/reconciles
→ AIDOS selects next valid actor
```

Session replacement must preserve this pattern.

## Workstreams

An accepted Definition may be decomposed into zero/one/many workstreams. Parallelization is optional and dependency-driven.

Use:

```text
schemas/workstream.schema.json
docs/WORKSTREAM_ORCHESTRATION.md
```

Each workstream carries identity, Definition binding, scope ownership, shared contracts, dependencies, blockers, resource claims and integration gates.

A local workstream result is not automatically an integrated project result. Applicable integration gates must pass.

Current execution lease semantics remain authoritative. Generic shared-resource/workstream leases are architecture/roadmap requirements until runtime-proven.

## Control plane and Human Input

Use:

```text
schemas/control-intent.schema.json
schemas/human-input-request.schema.json
docs/CONTROL_PLANE.md
protocols/INTERRUPTION_PROTOCOL.md
```

Supported conceptual control intents include `RUN`, `PAUSE`, `RESUME`, `SAFE_STOP`, `QUERY_STATUS`, `SUBMIT_HUMAN_INPUT`, `REQUEST_RECOVERY`.

A control intent is validated/applied by AIDOS; it is not itself a forced state transition.

The current top-level `WAITING_USER` state remains valid runtime semantics. A durable Human Input Request records the exact waiting reason/binding.

## Project/Definition applicability

Reusable profile categories:

```text
PRODUCT_ARCHETYPE
CAPABILITY
INTEGRATION
STACK
INFRASTRUCTURE
EXPOSURE_RISK
```

Project applicability lives at `.aidos/profile/PROJECT_APPLICABILITY.json`; per-Definition applicability lives at `.aidos/definitions/<definition_id>/v<version>/APPLICABILITY.json`.

Precedence:

```text
verified/accepted project truth
> explicit project override
> composed preset result
> generic heuristic
```

See `docs/PROFILE_PRESETS.md`.

## Definition progress

Definition convergence lives at:

```text
.aidos/definitions/<definition_id>/v<version>/PROGRESS.json
```

A new/rotated chat reads durable progress before continuing. The progress display is a control surface, not conversational decoration.

## Progress / ETA

Use `schemas/progress-estimate.schema.json` and `docs/PROGRESS_AND_ESTIMATION.md`.

Progress should be weighted from Definition/workstreams/dependencies/validation/integration where possible. ETA must carry confidence and may be `NOT_RELIABLY_ESTIMABLE`.

Never use an estimate as acceptance authority.

## Observability and learning

Use `docs/TELEMETRY.md`, `protocols/LEARNING_PROTOCOL.md` and `schemas/system-insight.schema.json`.

Learning maturity:

```text
OBSERVATION
→ HYPOTHESIS / learning candidate
→ explicit review/adoption
→ ADOPTED_IMPROVEMENT
```

A key maturity metric is whether human attention shifts from operational/technical intervention toward product, risk and strategy.

## Durable state and recovery

Chats/sessions are disposable. Essential state is reconstructed from project/workstream objects, events, Git bindings, leases, reviews, Human Input Requests and canonical project sources.

Do not recover workflow authority from prose summaries when durable state exists.

## Changes to AIDOS itself

Prefer:

```text
observed evidence
→ generalized observation/hypothesis
→ provenance/review
→ adopted profile/knowledge/protocol change
→ validator/tool/skill where possible
```

Executable prevention is preferred when the failure class is machine-detectable, but only after explicit adoption.
