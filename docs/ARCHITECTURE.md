# AIDOS architecture

## Purpose

AIDOS is the private orchestration, governance and learning layer around existing AI runtimes. Project preparation is deliberately separated from private Definition/Execution orchestration.

```text
AIDOS-Contracts
  → deterministic Project Baseline + Discovery Closure interfaces

AIDOS-Builder
  → Evidence Inventory / Project Baseline / Current Product State implementation

Project repository
  → accepted project truth + evidence + current product snapshot

AIDOS
  → private goal definition, orchestration, execution, review and learning
```

## Preparation architecture

The first source inventory is shared across preparation:

```text
Evidence Inventory
        │
        ├─ Project Baseline mapping
        │
        └─ Existing Project Discovery enrichment
             ├─ linked first-party source evidence
             └─ runtime observation evidence
```

Project mode then determines the gate:

```text
NEW_PROJECT
Accepted Project Baseline
→ Definition

EXISTING_PROJECT
Accepted Project Baseline
→ Existing Project Discovery
→ material product graph CLOSED
→ Accepted Current Product State
→ Definition
```

### Product boundary

For an existing product, the primary repository is the **discovery root**, not the assumed system boundary.

AIDOS-Builder builds an evidence-backed component graph:

```text
primary component
→ dependency
   ├─ FIRST_PARTY_MATERIAL → recursively discover component
   ├─ THIRD_PARTY_EXTERNAL → interface + relevant observable behaviour
   ├─ INFRASTRUCTURE       → infrastructure relationship/constraints
   └─ NON_MATERIAL         → explicit stop reason
```

Every `FIRST_PARTY` + `MATERIAL` component participates in closure and must have complete per-surface discovery coverage.

Core invariant:

> **Existing Project Discovery is complete only when AIDOS has closed the material product graph: all materially relevant first-party components and all reasonably observable runtime surfaces have either been discovered or are explicitly unresolved blockers.**

Because an explicit unresolved blocker means the graph is not closed, Current Product State acceptance remains blocked until it is resolved.

## Authority architecture

Three concerns remain separate:

### Project/source authority

`PROJECT_ACCESS.json` describes the primary build repository and explicitly declared project/context sources.

### Discovery authority

`DISCOVERY_AUTHORITY.json` governs evidence collection only.

Default discovery authority permits:

- passive read-only observation of known public runtime;
- read-only following of an evidence-linked material first-party source when accessible;
- no unrelated repository enumeration.

It forbids code changes, deploys, database writes, payments, side-effect forms and mutating admin actions. Active/authenticated runtime interaction requires an explicit bounded discovery grant.

### Execution authority

Private AIDOS Execution envelopes independently authorize technical mutation/deploy behaviour for one accepted goal. Discovery authority never expands execution authority.

## Current Product State

CPS is product-complete rather than repository-complete. It contains at least:

- `system_components`;
- `dependency_graph`;
- `runtime_surfaces`;
- discovery blockers/limitations;
- capabilities/flows;
- implementation/runtime/reconciliation state;
- evidence/provenance;
- explicit `CONFLICT`/`DRIFT`.

Required distinction:

```text
implementation state
!=
observed runtime state
```

Known public/passive runtime must be actually observed when reasonably reachable. `NOT_OBSERVED` cannot close that branch merely because source code exists or because repository access is bounded.

## Deterministic Discovery Closure

A CPS is acceptance-eligible only when deterministic validation proves:

1. all required global discovery surfaces are closed;
2. all disposition-required evidence is resolved;
3. all product mappings/references resolve;
4. every material first-party component is recursively complete;
5. every `FIRST_PARTY_MATERIAL` edge resolves to such a component;
6. all reasonably observable public/passive runtime has observation evidence;
7. capability/flow `NOT_OBSERVED` does not hide observation-required runtime;
8. no discovery blocker remains open.

Known defects, `CONFLICT` or `DRIFT` can remain because they describe known current reality.

## Runtime components

```text
Accepted preparation state
  │
  ▼
Human + Definition Agent
  │ defines desired delta
  ▼
Accepted Definition ───────────────┐
  │                                │
  ▼                                │ contradiction
Worker Agent                       │
  │                                │
  ▼                                │
Execution Envelope                 │
  │                                │
  ▼                                │
Local Bridge                       │
  ▼                                │
Execution Agent / Codex            │
  │                                │
  ▼                                │
Evidence + terminal handoff        │
  ▼                                │
Worker review ─────────────────────┘
```

If review discovers an omitted material first-party component, missing runtime branch or other closure failure:

```text
DISCOVERY_REFRESH_REQUIRED
→ AIDOS-Builder
→ reuse existing evidence/CPS
→ close only missing branches
→ accept new CPS
→ Definition consistency check
```

This is distinct from a product `CONTRADICTION`.

## Definition-first lifecycle

Once preparation is valid:

```text
accepted preparation state
→ goal-specific questions only
→ proposed Definition
→ human ACCEPTED
→ plan/Definition consistency
→ Execution
→ convergence review
```

For existing products, Definition is explicitly the desired delta from the accepted CPS.

## Launch discipline

For product/material releases, a Launch Definition defines the falsifiable release threshold before final launch pressure where practical.

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

After acceptance, release scope is frozen. New findings are classified as `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`. When all launch criteria pass, default state is `RELEASE_READY`.

## Separation of truth

### AIDOS-Contracts

Owns generic, versioned preparation contracts only.

### AIDOS-Builder

Owns distributable preparation procedures and deterministic validators.

### AIDOS

Owns private Definition/Worker/Execution/orchestration/review/learning capability.

### Project repository

Owns all project-specific accepted truth and durable state, including Baseline, Evidence Inventory, Discovery Authority, CPS/component graph/runtime observations, Definitions, executions and release state.

Principle: **Project-local truth; AIDOS-global capability.**

## Runtime binding and fail-closed behaviour

Existing-project execution binds at least:

```text
project_id
project_mode
repo/root/branch
accepted baseline commit
accepted CPS id + commit
CPS contract version
discovery catalog version
accepted Definition id/version
execution id/revision
```

Current AIDOS requires CPS/discovery contract/catalog `0.2.0` for existing-project execution. A stale/older accepted CPS is historical truth, not valid current preparation.

## Multi-project isolation

Repository/source/discovery/execution authority is project-scoped. Access to one project or a material component does not imply access to sibling projects. The dedicated runner must enforce per-project credential/root boundaries rather than relying only on agent instructions.
