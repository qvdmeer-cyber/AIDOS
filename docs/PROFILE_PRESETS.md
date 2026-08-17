# AIDOS composable profiles and presets

## Purpose

AIDOS should not repeatedly ask or rediscover facts that are strongly implied by a reusable product/technology pattern. At the same time, a preset must never become stronger than verified project evidence or an explicit human project decision.

Profiles therefore act as **versioned reusable hypotheses and applicability accelerators**, not project truth.

Primary objective:

```text
reusable project pattern
→ fewer applicability questions
→ fewer Definition questions
→ better execution context/validators
→ fewer Codex retries and GPT handoffs
```

## Composable profile layers

A project composes multiple independent profile categories:

```text
AIDOS Project Profile
├─ PRODUCT_ARCHETYPE     what/where the product fundamentally is
├─ CAPABILITY            what the product can do
├─ INTEGRATION           external systems/providers it talks to
├─ STACK                 technical implementation stack
├─ INFRASTRUCTURE        hosting/runtime environment
└─ EXPOSURE_RISK         operational/data/exposure characteristics
```

Exactly one `PRODUCT_ARCHETYPE` is selected. Other categories are composable.

Examples:

```text
CONTENT_WEBSITE
+ MULTILINGUAL
+ REACT
+ SHARED_LINUX_HOSTING
+ PUBLIC_INFORMATIONAL
```

or:

```text
MOBILE_APPLICATION
+ AUTHENTICATION
+ AI_ASSISTANT
+ OPENAI_API
+ AUTHENTICATED_USER_DATA
```

## Product Archetype versus capability/integration

Use this rule:

> **Product Archetype = what the product fundamentally is / where its primary interaction model runs. Capability = what it can do. Integration = what external system/provider it communicates with.**

Therefore:

- a native/cross-platform app is `MOBILE_APPLICATION`;
- a machine-interface service is `API_SERVICE`;
- a ChatGPT-hosted product is `CHATGPT_APP`;
- an MCP tool/resource server is `MCP_SERVER`;
- a normal web/mobile/API product that calls OpenAI remains its own archetype plus `OPENAI_API` integration.

Using an AI provider does not silently redefine the product archetype.

Initial archetypes live in `catalog/profile-presets.catalog.json` and include static/content websites, web/mobile/desktop applications, API/background/CLI services, libraries, browser extensions, CMS applications, ChatGPT apps and MCP servers.

## Development surfaces

`catalog/development-surfaces.catalog.json` owns reusable development concerns such as:

- UI structure;
- UX/interaction;
- visual design;
- responsive behaviour;
- accessibility;
- localization/content/SEO;
- APIs and tool contracts;
- conversation interaction;
- auth/authorization;
- data/background work/integrations/files;
- security/privacy;
- performance/runtime/observability/recovery;
- compatibility/migration/distribution/device/offline behaviour.

Presets classify these surfaces as:

- `APPLICABLE`;
- `CONDITIONAL`;
- `NOT_APPLICABLE`.

The project resolver combines selected presets into `.aidos/profile/PROJECT_APPLICABILITY.json`.

## Resolution and precedence

Multiple presets may classify the same surface differently. AIDOS resolves conservatively:

```text
APPLICABLE
> CONDITIONAL
> NOT_APPLICABLE
```

and records the tension.

This only resolves **preset-vs-preset hypotheses**. Actual authority is:

```text
verified current project evidence / explicit accepted project decision
> explicit project applicability override
> composed preset result
> generic AIDOS heuristic
```

A preset is never sufficient to mark an objective project fact verified. If a hosting preset suggests a runtime version but Discovery observes another version, Discovery wins and the contradiction becomes profile-evaluation evidence.

Provider-specific infrastructure profiles (for example a recurring hosting provider) should only acquire concrete defaults/constraints after they are evidence-backed. Do not invent provider facts merely because a provider-specific profile name exists.

## Project applicability versus Definition applicability

There are two independent questions:

```text
Project Applicability
= which development surfaces exist or may exist in this product?

Definition Applicability
= which of those surfaces are affected by this specific desired delta?
```

Example:

```text
Project: WEB_APPLICATION
UI                APPLICABLE
API               CONDITIONAL
Data              CONDITIONAL

Definition: add database index
UI                NOT_AFFECTED
API               NOT_AFFECTED
Data              AFFECTED
Performance        AFFECTED
```

`tools/New-AidosDefinitionApplicability.ps1` creates a durable per-Definition `APPLICABILITY.json` projection. A project-level `NOT_APPLICABLE` surface is automatically outside the Definition. Every other surface must be classified as `AFFECTED`, `NOT_AFFECTED` or remain `DECISION_REQUIRED`.

This prevents both failure modes:

- asking UI/design questions for an API-only project;
- silently forgetting UI/security/data/etc. when a project or delta actually touches them.

The six Definition concerns that are always core regardless of product shape are:

1. goal/scope;
2. current state and desired delta;
3. intended functional behaviour;
4. acceptance coverage;
5. out of scope;
6. unresolved assumptions.

Conditional development surfaces supplement these core concerns.

## Stack and infrastructure profiles

Stack/infrastructure profiles are not only applicability shortcuts. As AIDOS learns they may accumulate evidence-backed reusable assets such as:

- build/test/restore commands;
- known project-layout patterns;
- compatibility constraints;
- deployment patterns;
- validators;
- known failure signatures;
- preferred repair strategies;
- evidence expectations.

The goal is to move repeated reasoning downward:

```text
first occurrence
→ GPT diagnosis + Codex retries

repeated/proven pattern
→ profile knowledge

strong recurring invariant
→ validator/tool

later execution
→ earlier detection + less reasoning/retry/handoff
```

## Profile evaluation and learning

A profile must be measurable rather than becoming folklore.

`schemas/profile-evaluation.schema.json` supports signals/metrics including:

- defaults suggested/accepted/overridden;
- evidence contradictions;
- Definition questions avoided;
- Codex executions/repairs;
- GPT handoffs;
- validator preventions.

Evaluation can produce AIDOS learning candidates targeted at a profile. A repeated project-specific observation is not automatically promoted. Use the normal learning ladder:

```text
observed project result
→ candidate reusable profile lesson
→ evidence/provenance review
→ PROVEN
→ update versioned preset/knowledge
→ TOOLIZED where machine prevention is possible
```

A new preset version does not silently reinterpret older project state. Projects retain the exact preset versions used and may explicitly re-evaluate/migrate.

## Current integration boundary

This profile system is a reusable AIDOS Core foundation. It does not by itself change the accepted Project Baseline / Existing Project Discovery lifecycle contract. Lifecycle ordering and promotion semantics remain governed separately until that architecture is explicitly versioned.

Current Definition progress remains durable via `PROGRESS.json`; `APPLICABILITY.json` adds the missing project/delta applicability layer and is intended to drive the next Definition-surface contract version without relying on chat memory.
