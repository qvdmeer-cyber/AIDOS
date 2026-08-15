# Start AIDOS Project Documentation Builder

Use this entrypoint in a normal ChatGPT conversation to establish or refresh the software-project documentation for a repository.

## User start message

Existing project:

```text
Build/refresh the AIDOS project documentation for <PROJECT>.
Repository: <owner/repository or GitHub URL>.
Read https://github.com/qvdmeer-cyber/AIDOS/blob/main/START_PROJECT_DOCUMENTATION.md first.
```

New project:

```text
Start the AIDOS project documentation baseline for <PROJECT>.
Repository: <owner/repository or GitHub URL>.
Read https://github.com/qvdmeer-cyber/AIDOS/blob/main/START_PROJECT_DOCUMENTATION.md first.
```

## Agent bootstrap

Read in this order:

1. `agents/PROJECT_DOCUMENTATION_AGENT.md`;
2. `protocols/PROJECT_DOCUMENTATION_PROTOCOL.md`;
3. `docs/PROJECT_DOCUMENTATION_BUILDER.md`;
4. the target project's `.aidos/PROJECT.json` and `AGENTS.md` when present;
5. the target repository tree and existing documentation/configuration sources.

## Required start behaviour

1. Determine `NEW_PROJECT`, `EXISTING_PROJECT` or `REFRESH` from repository state/user request.
2. Inventory the project **before** asking the user questions.
3. If `.aidos/documentation/` state is absent, create/initialize it using the AIDOS contracts or equivalent valid files.
4. Reuse existing reliable project documentation; do not create duplicates merely to match an AIDOS structure.
5. Build the concern coverage/provenance map.
6. Resolve objective repository-derived facts without asking the user.
7. Identify the first material human-owned gap or conflict.
8. Ask **one question only**, preferably with bounded answer options plus `Other`.
9. Persist progress after each accepted answer so another GPT chat can resume from repository state.
10. Continue one question per turn until the baseline can be proposed.
11. Present a compact final coverage summary and request explicit acceptance.
12. After acceptance, mark the baseline accepted with the repository commit and leave the project ready for the AIDOS Definition Agent.

## Scope boundary

This builder covers software-project/product/technical truth needed by development agents.

It explicitly does **not** run the old organisation/business-documentation workflow and does not create marketing, HR, sales, company-policy or broad organisation-governance documentation.

## Chat rotation

If the chat becomes bloated or confused, start a new normal ChatGPT conversation with the same start message. The new agent must resume from project repository state; do not rely on a prose summary from the old chat as canonical truth.
