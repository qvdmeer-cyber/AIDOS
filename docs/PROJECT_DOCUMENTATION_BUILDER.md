# Project Documentation Builder

## Why it exists

AIDOS agents should not have to rediscover stable project truth from source code and old chats for every development goal. The Project Documentation Builder creates a durable, project-local map of the sources an agent should trust.

It is intentionally different from the Definition Agent:

```text
Project Documentation Builder
  -> stable project truth and canonical sources

Definition Agent
  -> what a specific development goal must become

Worker Agent
  -> how an accepted goal is bounded/reviewed

Execution Agent
  -> technical execution
```

## Single-source-of-truth design

AIDOS does not impose a second documentation tree on integrated projects.

Example existing project:

```text
README.md                         -> product/identity overview
docs/architecture/SYSTEM.md      -> architecture
docs/runtime/ROUTING.md          -> runtime topology
docs/DEPLOYMENT.md               -> deployment/rollback
src/...                           -> implementation, not documentation duplicate
.aidos/documentation/MANIFEST.json -> pointers + coverage/provenance
```

The manifest is an index/contract, not a copied knowledge base.

## Project-local state

Recommended integration state:

```text
<Project>/
  .aidos/
    PROJECT.json
    AGENT_PROFILE.json
    documentation/
      MANIFEST.json
      SESSION.json
```

`MANIFEST.json` records the accepted baseline, concern coverage, canonical sources and provenance.

`SESSION.json` records an in-progress inventory/interview so a conversation can be replaced without losing decisions.

The actual documentation stays wherever the project has chosen as its canonical home.

## Concern model

AIDOS currently recognizes these broad concerns:

| Concern | Typical truth |
|---|---|
| identity | project/repo/root/boundaries |
| product | stable purpose and scope |
| architecture | components and boundaries |
| runtime | hosts/processes/routing/topology |
| data | storage/schema/lifecycle |
| interfaces | APIs/external integrations |
| development | setup/toolchains/commands |
| validation | tests/acceptance/validators |
| deployment | environments/release/rollback |
| security_privacy | auth/data/credential boundaries |
| operations | health/logging/recovery where relevant |
| decisions | durable architectural/technical decisions |
| constraints | legacy/material limitations |

This is a coverage vocabulary, not a mandatory file-per-concern structure.

## Evidence classes

A fact used by the builder is classified as:

- `REPO_VERIFIED` — objective current project evidence supports it;
- `HUMAN_ACCEPTED` — project owner explicitly confirmed it;
- `INFERRED` — plausible interpretation that still needs proof/acceptance;
- `UNKNOWN` — not known;
- `CONFLICT` — credible sources disagree.

An accepted baseline must not depend on silent inference.

## Existing-project algorithm

```text
repository inventory
  -> candidate-source discovery
  -> coverage map
  -> duplicate/conflict detection
  -> objective fact extraction
  -> material gap classification
  -> one-question interview (only where needed)
  -> update/create minimal canonical sources
  -> proposed baseline
  -> human acceptance
  -> manifest ACCEPTED
```

The builder should preserve working project documentation rather than reorganize a repository for aesthetic consistency.

## New-project algorithm

A new repository will naturally have less project truth. The builder establishes only the stable baseline needed to orient future agents. Goal-specific functionality remains for the Definition Agent.

The builder may establish, for example:

- project identity/repository/root;
- stable product purpose;
- initial architecture/runtime constraints that have genuinely been decided;
- intended local development/runtime environment;
- material security/data boundaries;
- where future decisions/docs will live.

It must not invent a full future system architecture simply to make the documentation look complete.

## Interaction model

The user experience is deliberately conversational:

```text
Builder inventories everything it can.

Question 1
A / B / C / Other

user answers
-> persisted

Question 2
...
```

Only one material question is asked per turn. The next question may depend on the previous answer.

## Baseline acceptance

`ACCEPTED` means the documentation set is currently trustworthy enough to orient AIDOS development. It does not mean every possible technical topic has a document.

A concern may be `NOT_APPLICABLE`, and non-material detail may remain undocumented.

The acceptance gate focuses on preventing agents from being materially misled by missing, contradictory, inferred or duplicate project truth.

## Maintenance

Documentation is expected to evolve with the project.

During an execution:

- straightforward technical changes should update their canonical source when relevant;
- Worker may mark a concern stale when evidence and docs diverge;
- product contradictions go to the Definition Agent;
- stable project-level contradictions may reopen Project Documentation Builder.

A refresh produces a new documentation baseline revision.

## Relation to AIDOS learning

Project documentation answers: **what is true here?**

AIDOS learning answers: **what generic capability/pattern should future agents know?**

Example:

```text
Project truth:
SocialScans host X has a child-application boundary at Y.

Potential AIDOS learning:
For IIS child applications, validate deployment root against application boundary before sync.
```

The first stays in the project; only the generalized second statement may become an AIDOS learning candidate.

## Current implementation

Available now:

- Project Documentation Agent contract;
- Project Documentation Protocol;
- project documentation manifest/session JSON schemas;
- manifest template;
- `New-AidosProjectDocumentation.ps1` bootstrap tool;
- `Test-AidosProjectDocumentation.ps1` baseline validator;
- ChatGPT entrypoint `START_PROJECT_DOCUMENTATION.md`.

The later bridge can invoke and validate the same project-local contracts; the documentation builder does not depend on the bridge to be useful.
