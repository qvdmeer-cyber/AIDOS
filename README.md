# AIDOS

**Artificial Intelligence Development Operating System**

AIDOS is the private core for human-governed AI software development. It separates project preparation, human-accepted goal definition, high-value reasoning, technical execution, review, release governance, recovery and reusable learning so AI agents can work autonomously inside explicit boundaries without making product decisions on behalf of the human owner.

## Ecosystem boundary

```text
AIDOS-Contracts
  → Project Baseline + Discovery Closure contracts

AIDOS-Builder
  → distributable Project Baseline + Existing Project Discovery

Project repository
  → project truth + evidence + accepted preparation state

AIDOS
  → private Definition / Worker / Execution / review / learning runtime
```

The private AIDOS core does not need to be shared with collaborators who only use AIDOS-Builder.

## Preparation gate

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

For an existing product, the primary repository is only the discovery starting point. AIDOS-Builder must recursively close materially relevant first-party components and reasonably observable runtime before the Current Product State is eligible for acceptance.

Core Discovery Closure invariant:

> **Existing Project Discovery is complete only when AIDOS has closed the material product graph: all materially relevant first-party components and all reasonably observable runtime surfaces have either been discovered or are explicitly unresolved blockers.**

An explicit unresolved blocker keeps discovery incomplete.

## Discovery authority is not execution authority

Project/source access, discovery authority and execution authority are separate.

AIDOS-Builder Discovery Authority may automatically allow:

- passive read-only observation of known public runtime;
- read-only following of an evidence-linked `FIRST_PARTY_MATERIAL` source when accessible.

It does not grant permission to modify code, deploy, write databases, make payments, submit side-effect forms or perform mutating admin actions. Active/authenticated discovery requires its own bounded grant.

AIDOS Core execution remains governed independently by the accepted Execution authority envelope.

## Core flow

```text
Accepted preparation state
  ↓
Definition Agent + Human
  ↓
ACCEPTED DEVELOPMENT DEFINITION
  ↓
Worker Agent
  ↓
Execution Agent / Codex
  ↓
Evidence + Review
  ↓
Worker Agent
  ├─ PASS
  ├─ REPAIR → Execution Agent
  ├─ DISCOVERY_REFRESH_REQUIRED → AIDOS-Builder
  ├─ CONTRADICTION → Definition Agent + Human
  └─ GATE/BLOCKER → Human
```

For existing projects, execution binds the exact closure-compatible Current Product State version/commit used by Definition.

## Core rules

1. **Accepted project truth before goal definition.** A compatible accepted Project Baseline is mandatory.
2. **Product-complete current state before change definition.** An existing product additionally requires an accepted Current Product State under current Discovery Closure rules.
3. **Definition is delta-only for existing projects.** Existing functionality is evidence, not a product question to rediscover.
4. **Definition before execution.** The human explicitly accepts foreseeable changed behaviour, constraints and acceptance criteria.
5. **Project-local truth.** Baseline, evidence, component graph, runtime observations, CPS, Definitions and project-specific truth stay in the project repository.
6. **AIDOS-global capability.** Generic runtime agents, protocols, validators, reusable profiles and reusable learning live once in AIDOS.
7. **Goal-scoped context.** Agents load only relevant generic profile/capability/goal knowledge plus bound project truth.
8. **Bounded autonomy.** Execution continues while useful inside accepted goal/authority and stops at material boundaries or terminal completion.
9. **Frozen launch criteria.** Once accepted launch criteria pass, improvement alone is not sufficient grounds for delay; default state is `RELEASE_READY` unless release scope is explicitly reopened.

## Composable project profiles

AIDOS uses composable, versioned profiles to avoid repeating the same applicability reasoning and Definition questions across projects.

```text
Project Profile
├─ PRODUCT_ARCHETYPE
├─ CAPABILITY
├─ INTEGRATION
├─ STACK
├─ INFRASTRUCTURE
└─ EXPOSURE_RISK
```

Exactly one Product Archetype defines what/where the product fundamentally is. Other layers compose around it.

Examples of Product Archetypes include:

```text
STATIC_MARKETING_SITE
CONTENT_WEBSITE
WEB_APPLICATION
MOBILE_APPLICATION
DESKTOP_APPLICATION
API_SERVICE
BACKGROUND_SERVICE
CLI_APPLICATION
LIBRARY_PACKAGE
BROWSER_EXTENSION
CMS_APPLICATION
CHATGPT_APP
MCP_SERVER
```

A provider/integration is not an archetype. For example, a web/mobile/API product using OpenAI remains its actual Product Archetype plus the `OPENAI_API` Integration profile.

Profiles map to reusable development surfaces such as UI/UX/design, API/tool contracts, localization, auth, data, background work, integrations, security/privacy, runtime, observability, recovery and compatibility.

Two applicability layers are kept distinct:

```text
Project Applicability
= which development surfaces exist or may exist in this product?

Definition Applicability
= which of those surfaces are affected by this specific desired delta?
```

This lets an API-only project exclude UI/design while preventing a UI-bearing project from silently omitting UI/UX/design when a delta actually affects it.

Profiles are accelerators, never truth. Verified project evidence and explicit human-accepted project decisions always override preset assumptions.

Profile effectiveness is evaluated over time (overrides, evidence contradictions, avoided questions, Codex retries, GPT handoffs, validator prevention). Proven recurring lessons can update versioned profiles and eventually become validators/tools.

See `docs/PROFILE_PRESETS.md`.

## Discovery refresh

A previously accepted CPS is not silently reinterpreted under stronger discovery rules.

```text
accepted old CPS
→ preserve as historical lineage
→ DISCOVERY_REFRESH_REQUIRED
→ reuse existing evidence/current-state facts
→ discover only missing material branches/runtime observations
→ deterministic closure PASS
→ accept new CPS
```

Definition and Worker must route a material missing component/runtime branch back to AIDOS-Builder rather than absorbing that discovery into goal reasoning.

## Launch governance

For a product/material release, establish an accepted Launch Definition before the final development phase where practical:

```text
Accepted Launch Definition
→ RELEASE_SCOPE_FROZEN
→ final accepted work
→ launch criteria PASS
→ RELEASE_READY
→ release / real-user evidence
```

After freeze, new findings are `LAUNCH_BLOCKER`, `POST_LAUNCH` or `EVIDENCE_REQUIRED`. Useful non-blocking ideas go to the post-launch backlog. Delaying after `RELEASE_READY` requires explicit reopen with reason/consequence.

See `protocols/LAUNCH_PROTOCOL.md`.

## Agent model

- **Definition Agent** — consumes accepted preparation state, resolves project/delta applicability, defines only the desired delta and obtains human acceptance.
- **Worker Agent** — plans bounded execution, reviews evidence, detects stale/incomplete CPS, enforces release-scope discipline and controls transitions.
- **Execution Agent** — technical execution only inside exact accepted bindings/authority.

Project Baseline and Existing Project Discovery/Discovery Closure are owned externally by AIDOS-Builder + AIDOS-Contracts.

## Knowledge inheritance

```text
AIDOS Core
→ relevant profile/capability knowledge
→ relevant goal-pattern knowledge
→ accepted Project Baseline
→ accepted closure-compatible Current Product State (EXISTING_PROJECT)
→ accepted Definition
→ accepted Launch Definition where applicable
→ current Execution
```

More specific accepted project truth wins over profiles/generic heuristics.

## Durable state

Chats and Codex sessions are disposable. Essential state must be reconstructable from repository state/events.

The project repository owns:

- Project Baseline;
- Evidence Inventory;
- Discovery Authority and discovery state;
- CPS including system components/dependency graph/runtime evidence;
- project applicability profile;
- Definition applicability/progress;
- Definitions/executions/reviews;
- release state/backlog.

AIDOS consumes these objects; it does not turn chat memory into canonical truth.

## Current implementation status

The private AIDOS foundation is present. Existing-project onboarding now fails closed unless Evidence Inventory 0.2 and an accepted CPS/discovery state under Discovery Closure 0.2 are present with no open discovery blocker.

Composable profile/applicability foundation is present in AIDOS Core: development-surface/preset catalogs, project/Definition applicability schemas, resolver tooling, profile evaluation schema and profile-targeted learning classification. This foundation does **not** itself change the current Project Baseline/Discovery lifecycle ordering; that remains a separately versioned governance decision.

The local multi-project bridge, Codex lifecycle, review transport, desktop ChatGPT integration and crash reconciliation remain the main runtime implementation work.

The existing Workflow V2 remains separate as a fallback.
