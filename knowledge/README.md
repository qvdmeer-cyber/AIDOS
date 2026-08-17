# AIDOS knowledge

AIDOS knowledge is organized by applicability, not by source project.

```text
knowledge/
├─ core/          always-relevant operating knowledge
├─ profiles/      reusable knowledge attached to product/stack/infra/etc. profiles
├─ capabilities/  e.g. database, auth, deployment, routing, testing
└─ goals/         reusable development-goal/problem patterns
```

Project-specific facts do not belong here.

## Profiles

Composable AIDOS profiles are defined in `catalog/profile-presets.catalog.json` and described in `docs/PROFILE_PRESETS.md`.

Profile-targeted knowledge may include evidence-backed recurring constraints, validators, failure signatures or execution guidance for a Product Archetype, Capability, Integration, Stack, Infrastructure or Exposure/Risk profile.

A profile remains an applicability/default accelerator, not project truth. Its learned knowledge must retain evidence/provenance and exact profile version applicability.

## Retrieval

Worker selects the minimum useful set for the current execution. The existence of knowledge does not imply it should enter every model context.

Project/Definition applicability should narrow retrieval further: do not load UI knowledge for an API-only Definition or provider-specific hosting knowledge for an unrelated runtime.

## Precedence

```text
accepted Definition/current Execution
> verified/accepted project truth
> explicit project applicability override
> AIDOS goal knowledge
> AIDOS profile/capability knowledge
> generic heuristic
```

AIDOS global knowledge or a preset can never silently override accepted/project truth.
