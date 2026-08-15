# Launch and release governance protocol

## Purpose

Prevent release scope from expanding indefinitely after a product has already reached the quality level that was deliberately accepted as sufficient for real users.

AIDOS must bound not only execution autonomy, but also **pre-launch scope expansion by the product owner**.

Core principle:

> **Launch criteria are defined before launch pressure exists. Once satisfied, improvement alone is not sufficient grounds for delay.**

The objective is not lower quality. The objective is to preserve an explicit quality threshold long enough to reach users, then use real evidence to guide further improvement.

## Launch Definition / Release Gate

For a product or material release, establish a project-local **Launch Definition** before the final development phase wherever practical.

The Launch Definition contains explicit, falsifiable criteria for when the release is good enough to reach real users, including as relevant:

- core product promise and critical user flows;
- material security/privacy/data-integrity/compliance requirements;
- minimum reliability/recovery expectations;
- release-critical compatibility/runtime/deployment requirements;
- required evidence and validators;
- explicitly excluded improvements or deferred scope;
- release identity/version and intended audience/environment;
- human acceptance/version/timestamp.

The Launch Definition is separate from ordinary implementation optimism or subjective polish. It must be specific enough that Worker can determine whether launch criteria are PASS/FAIL without asking whether the owner can imagine additional improvements.

## Scope freeze

After human acceptance of a Launch Definition:

- the release scope is frozen;
- new feature ideas, refinements and quality improvements do not silently enter the release;
- accepted launch criteria may only change through an explicit reopen/version event;
- useful deferred work is preserved in the project-local post-launch backlog rather than lost.

## Classification of new findings after scope freeze

Every material new insight affecting the frozen release is classified as exactly one of:

### `LAUNCH_BLOCKER`

A release-blocking finding must be objectively material to the accepted release, such as:

- the core product promise does not work;
- a critical accepted user flow fails materially;
- material security/privacy vulnerability;
- credible data-loss/data-integrity risk;
- compliance/legal requirement required for the intended launch is not met;
- similarly severe defect that makes releasing inconsistent with the accepted Launch Definition.

A blocker must state the violated launch criterion or the objective risk that makes the existing Launch Definition invalid.

### `POST_LAUNCH`

Useful improvement that is not required to satisfy the accepted Launch Definition.

Examples include:

- nicer UX/polish beyond accepted criteria;
- additional feature ideas;
- refactoring without release-critical impact;
- further performance/observability improvement above accepted threshold;
- an alternative implementation that may be cleaner but is not necessary for safe launch.

`POST_LAUNCH` work is preserved and must not delay the frozen release.

### `EVIDENCE_REQUIRED`

There is a plausible concern, but insufficient evidence that it is release-critical.

Default action:

- do not expand release scope merely because the concern is imaginable;
- identify the evidence needed to decide;
- where safe, obtain that evidence from controlled testing or real post-launch usage;
- promote to `LAUNCH_BLOCKER` only when evidence supports the material blocker claim;
- otherwise route to `POST_LAUNCH`.

## Invalid blocker rationales

The following are not sufficient on their own:

- "this can be better";
- "this does not feel finished";
- "we could also add ...";
- preference for a cleaner implementation without release-critical consequence;
- a new product idea discovered after scope freeze;
- speculative concern without evidence or a violated accepted criterion.

## Release-ready default

When every accepted Launch Definition criterion is PASS and no unresolved `LAUNCH_BLOCKER` remains:

```text
RELEASE_READY
```

is the default state.

Worker must proceed toward the already-authorized release lifecycle or stop at the next genuine release authority gate. It must **not** ask the product owner whether additional improvements should be added first.

## Explicit delay / reopen

Delaying release after `RELEASE_READY` is a deliberate exception.

It requires:

1. explicit human decision to reopen the Launch Definition/release scope;
2. recorded reason;
3. new/changed launch criterion or scope item;
4. stated consequence for release timing/risk where knowable;
5. new Launch Definition version and renewed acceptance.

The previous accepted version remains part of the durable lineage.

## Post-launch optimization

After launch, prefer observed evidence from real use over speculative pre-launch refinement:

- user behaviour and failures;
- support/feedback patterns;
- measured performance/reliability;
- conversion/adoption/retention where relevant;
- validated usability problems;
- security/operations evidence.

AIDOS should make post-launch learning easy, not turn pre-launch uncertainty into permanent scope expansion.

## Relationship to other protocols

- **Definition Agent** helps establish/reopen the Launch Definition with the human.
- **Worker Agent** enforces scope freeze, classifies findings and drives `RELEASE_READY` when criteria pass.
- **Execution Agent** executes accepted release work but cannot add improvements to frozen scope.
- **Review protocol** checks both Definition convergence and Launch Definition convergence when a release gate applies.
- **Learning protocol** may generalize proven release-governance lessons, but may never silently change project-specific launch criteria.

Machine-readable Launch Definition/state/backlog contracts belong to later runtime implementation work. This protocol establishes the architectural governance invariant first.
