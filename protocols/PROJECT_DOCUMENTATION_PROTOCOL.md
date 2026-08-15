# AIDOS Project Documentation Protocol

## Purpose

Create or refresh a project-local documentation baseline without duplicating reliable sources and without mixing project truth into the AIDOS repository.

## State model

```text
UNINITIALIZED
  -> INVENTORY
  -> GAP_ANALYSIS
  -> INTERVIEW            # only when material human-owned truth is missing/conflicting
  -> PROPOSED_BASELINE
  -> ACCEPTED
  -> MAINTENANCE
```

A refresh uses:

```text
ACCEPTED
  -> REFRESH_INVENTORY
  -> GAP_ANALYSIS
  -> INTERVIEW?           # only if needed
  -> PROPOSED_BASELINE
  -> ACCEPTED (new baseline revision)
```

## 1. Bootstrap

Read, in order:

1. AIDOS `agents/PROJECT_DOCUMENTATION_AGENT.md`;
2. this protocol;
3. project `.aidos/PROJECT.json` if present;
4. project `AGENTS.md` if present;
5. repository tree and candidate documentation/configuration sources.

Do not assume a conventional documentation layout.

## 2. Read-only inventory first

Before asking the human anything, inspect what can be established from the repository.

Candidate evidence includes:

- README and docs;
- source/package/project manifests;
- solution/workspace files;
- CI configuration;
- test projects and acceptance scripts;
- infrastructure/deployment configuration;
- database/schema/migration files;
- API contracts;
- runtime/hosting configuration;
- project-local agent instructions;
- durable decision records.

Produce an internal source inventory with path, concern, freshness signal and confidence.

## 3. Coverage and provenance

For each applicable documentation concern set:

- `status`: `COVERED | PARTIAL | MISSING | CONFLICT | NOT_APPLICABLE`;
- one `canonical_source` where covered;
- supporting sources/evidence;
- provenance class: `REPO_VERIFIED | HUMAN_ACCEPTED | INFERRED | UNKNOWN | CONFLICT`;
- material gap, if any.

A concern may have supporting sources but only one canonical source per specific truth-domain unless the manifest explicitly partitions the domain.

## 4. Single-source reconciliation

When multiple documents overlap:

1. determine whether they describe distinct scopes;
2. if not, establish which source is authoritative/current;
3. convert the non-canonical source to a pointer, archive/remove it when authorized, or mark a cleanup action;
4. never silently merge contradictory facts.

The builder optimizes for **fewer authoritative sources**, not for a fixed AIDOS folder structure.

## 5. Gap classification

A gap is one of:

- `DERIVABLE` — can be established objectively from current repository/runtime evidence;
- `HUMAN_FACT` — stable project truth only the human/project owner can confirm;
- `PROJECT_DECISION` — durable project-level choice needed for future development;
- `GOAL_SPECIFIC` — belongs to a current/future Definition, not baseline documentation;
- `NON_MATERIAL` — can remain undocumented for now.

Only `HUMAN_FACT` and `PROJECT_DECISION` normally enter the interview.

## 6. Interview

Ask exactly one material question per turn.

Question format should be compact:

```text
Question <n>: <decision/fact>
A. ...
B. ...
C. ...
Other: ...

Why this matters: <one short sentence, only when useful>
```

Do not present a questionnaire batch. Do not ask the user to restate facts already supported by reliable project sources.

Persist each accepted answer into project-local documentation-session state immediately.

## 7. Drafting/updating project sources

Use this precedence:

1. update an existing canonical source when it already owns the concern;
2. extend an existing appropriate source when that preserves clarity;
3. create a new focused project document only when no good canonical home exists.

Do not generate generic documentation simply because a template exists.

## 8. Proposed baseline

Before acceptance, show a compact summary:

```text
Covered: X
Partial: Y
Not applicable: Z
Open material gaps: 0
Conflicts: 0
New docs: ...
Updated docs: ...
Canonical source changes: ...
```

The full truth remains in the project repo, not in the chat summary.

## 9. Acceptance gate

Set documentation baseline `ACCEPTED` only if:

- all material conflicts are resolved or explicitly accepted as known constraints;
- no material human-owned truth remains `UNKNOWN`;
- inferred claims have either evidence or explicit acceptance;
- the manifest identifies canonical sources for applicable concerns;
- there is no known duplicate source-of-truth ambiguity that would materially mislead agents;
- the human explicitly accepts the baseline.

Acceptance records baseline revision and repository commit.

## 10. Definition handoff

An accepted documentation baseline is an input to the Definition Agent. It does not itself authorize implementation.

```text
Project Documentation ACCEPTED
  -> Definition Agent may define a development goal
  -> Definition ACCEPTED
  -> Worker may create execution
```

## 11. Maintenance and staleness

Executions that change documented truth should update the canonical project source where feasible. The Worker may set a documentation concern `STALE` when evidence shows the baseline no longer matches the project.

Material staleness blocks new Definitions only when it could reasonably cause incorrect product/architecture decisions. Otherwise refresh can occur independently.

## 12. Context rotation

Because inventory, answers, canonical mappings and open gaps are persisted project-locally, a Project Documentation Agent chat can be rotated at any point. A new chat resumes from repository state, not from a prose handoff from the old chat.

## 13. Learning

After completion, identify only reusable AIDOS-level learnings about documentation discovery, validation, source selection or tooling. Project facts never become global AIDOS knowledge merely because they were discovered by this process.
